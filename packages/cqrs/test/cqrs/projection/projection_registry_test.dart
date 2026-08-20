import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectionRegistry.add', () {
    test('rejects an empty name', () {
      expect(
        () => ProjectionRegistry().add(_TestProjection(name: ' \t')),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects surrounding name whitespace', () {
      expect(
        () => ProjectionRegistry().add(_TestProjection(name: ' spaced ')),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects non-positive versions', () {
      for (final version in [0, -1]) {
        expect(
          () => ProjectionRegistry().add(
            _TestProjection(name: 'version-$version', version: version),
          ),
          throwsA(isA<ProjectionConfigurationException>()),
        );
      }
    });

    test('rejects an empty stream route pattern', () {
      expect(
        () => ProjectionRegistry().add(
          _TestProjection(streamRoute: const _TestStreamRoute(' \t')),
        ),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects duplicate names from distinct projections', () {
      final registry =
          ProjectionRegistry()..add(_TestProjection(name: 'duplicate'));

      expect(
        () => registry.add(_TestProjection(name: 'duplicate')),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects additions after freezing', () {
      final registry = ProjectionRegistry()..freeze();

      expect(
        () => registry.add(_TestProjection()),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });
  });

  group('ProjectionRegistry.prepare', () {
    test('resets a missing projection and starts it at zero', () async {
      final projection = _TestProjection();
      final registry = ProjectionRegistry()..add(projection);
      final runtimeStore = _FakeRuntimeStore();

      final prepared = await registry.prepare(runtimeStore, forceReset: false);

      expect(prepared.single.position, 0);
      expect(projection.resetCount, 1);
      expect(runtimeStore.resetNames, ['projection']);
    });

    test('retains a matching consistent position without resetting', () async {
      final projection = _TestProjection(version: 3);
      final registry = ProjectionRegistry()..add(projection);
      final runtimeStore = _FakeRuntimeStore(
        positions: {
          projection.name: ProjectionAtSequence(
            version: 3,
            scannedThroughLocalSequence: 12,
          ),
        },
      );

      final prepared = await registry.prepare(runtimeStore, forceReset: false);

      expect(prepared.single.position, 12);
      expect(projection.resetCount, 0);
      expect(runtimeStore.resetNames, isEmpty);
    });

    test('resets a projection whose version changed', () async {
      final projection = _TestProjection(version: 2);
      final registry = ProjectionRegistry()..add(projection);
      final runtimeStore = _FakeRuntimeStore(
        positions: {
          projection.name: ProjectionAtSequence(
            version: 1,
            scannedThroughLocalSequence: 12,
          ),
        },
      );

      final prepared = await registry.prepare(runtimeStore, forceReset: false);

      expect(prepared.single.position, 0);
      expect(projection.resetCount, 1);
    });

    test('resets an inconsistent projection', () async {
      final projection = _TestProjection();
      final registry = ProjectionRegistry()..add(projection);
      final runtimeStore = _FakeRuntimeStore(
        positions: {projection.name: const ProjectionInconsistent()},
      );

      final prepared = await registry.prepare(runtimeStore, forceReset: false);

      expect(prepared.single.position, 0);
      expect(projection.resetCount, 1);
    });

    test('force reset discards a matching consistent position', () async {
      final projection = _TestProjection();
      final registry = ProjectionRegistry()..add(projection);
      final runtimeStore = _FakeRuntimeStore(
        positions: {
          projection.name: ProjectionAtSequence(
            version: projection.version,
            scannedThroughLocalSequence: 12,
          ),
        },
      );

      final prepared = await registry.prepare(runtimeStore, forceReset: true);

      expect(prepared.single.position, 0);
      expect(projection.resetCount, 1);
    });

    test('prepares projection resets concurrently', () async {
      final bothStarted = Completer<void>();
      final release = Completer<void>();
      final started = <String>{};

      Future<void> waitForRelease(String name) {
        started.add(name);
        if (started.length == 2) bothStarted.complete();
        return release.future;
      }

      final registry =
          ProjectionRegistry()
            ..add(
              _TestProjection(
                name: 'first',
                onReset: () => waitForRelease('first'),
              ),
            )
            ..add(
              _TestProjection(
                name: 'second',
                onReset: () => waitForRelease('second'),
              ),
            );

      final preparing = registry.prepare(
        _FakeRuntimeStore(),
        forceReset: false,
      );
      await bothStarted.future;
      expect(started, {'first', 'second'});

      release.complete();
      await preparing;
    });

    test('propagates reset failures', () async {
      final error = Exception('reset failed');
      final registry =
          ProjectionRegistry()
            ..add(_TestProjection(onReset: () async => throw error));

      await expectLater(
        registry.prepare(_FakeRuntimeStore(), forceReset: false),
        throwsA(same(error)),
      );
    });
  });
}

final class _TestProjection implements Projection<String, String> {
  @override
  final String name;
  @override
  final int version;
  @override
  final StreamRoute<String> streamRoute;
  final Future<void> Function()? _onReset;
  int resetCount = 0;

  _TestProjection({
    this.name = 'projection',
    this.version = 1,
    this.streamRoute = const StreamRouteAll(),
    Future<void> Function()? onReset,
  }) : _onReset = onReset;

  @override
  Future<void> reset() async {
    resetCount++;
    await _onReset?.call();
  }

  @override
  Future<void> apply(
    String streamParams,
    String event,
    EventMetadata metadata,
  ) async {}

  @override
  void onBatchApplied() {}
}

final class _TestStreamRoute extends StreamRoute<String> {
  @override
  final String pattern;

  const _TestStreamRoute(this.pattern);

  @override
  PatternFilter get filter => PatternFilter.exact(pattern);

  @override
  String buildPath(String streamParams) => streamParams;

  @override
  String parseParams(String streamPath) => streamPath;
}

final class _FakeRuntimeStore implements RuntimeStoreProjection {
  final Map<String, ProjectionPosition> positions;
  final List<String> resetNames = [];

  _FakeRuntimeStore({Map<String, ProjectionPosition>? positions})
    : positions = {...?positions};

  @override
  Future<ProjectionPosition> getProjectionPosition(String name) async {
    return positions[name] ?? const ProjectionNotInitialized();
  }

  @override
  Future<void> resetProjection(
    String name,
    int version,
    Future<void> Function() action,
  ) async {
    resetNames.add(name);
    await action();
    positions[name] = ProjectionAtSequence(
      version: version,
      scannedThroughLocalSequence: 0,
    );
  }

  @override
  Future<void> advanceProjection(
    String name,
    int currentSequence,
    int targetSequence,
    Future<void> Function() action,
  ) async {
    await action();
  }
}
