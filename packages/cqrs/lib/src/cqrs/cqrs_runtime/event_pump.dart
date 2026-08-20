import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/projection_page_adapter.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';

typedef AppliedEventReaderFactory =
    PaginatedReader<LocalEvent> Function(int localSequenceCursor);

/// Applies committed events to prepared projections from their durable
/// positions.
///
/// Create one pump after preparing every projection and call [pump] whenever
/// durable history may have advanced. Callers do not pass events. Concurrent
/// calls share the active work and request another scan. Durable local
/// sequences must be contiguous from the scan's starting position.
///
/// ```dart
/// final projections = await projectionRegistry.prepare(
///   runtimeStore,
///   forceReset: false,
/// );
/// final pump = EventPump(
///   createReader: eventStore.getAppliedEventReader,
///   eventRegistry: eventRegistry,
///   projections: projections,
/// );
/// await pump.pump();
/// ```
final class EventPump {
  final AppliedEventReaderFactory _createReader;
  final EventRegistry _eventRegistry;
  final List<PreparedProjectionPageAdapter> _projections;

  Future<void>? _active;
  bool _scanRequested = false;

  EventPump({
    required AppliedEventReaderFactory createReader,
    required EventRegistry eventRegistry,
    required List<PreparedProjectionPageAdapter> projections,
  }) : _createReader = createReader,
       _eventRegistry = eventRegistry,
       _projections = List.unmodifiable(projections);

  Future<void> pump() {
    _scanRequested = true;
    final active = _active;
    if (active != null) return active;

    final completer = Completer<void>();
    _active = completer.future;
    _drain(completer);
    return completer.future;
  }

  Future<void> _drain(Completer<void> completer) async {
    try {
      // keep scanning if needed
      do {
        _scanRequested = false;
        await _scan();
      } while (_scanRequested);

      _active = null;
      completer.complete();
    } catch (error, stackTrace) {
      _active = null;
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> _scan() async {
    if (_projections.isEmpty) return;

    // find the earliest position to start scanning from
    // The discrepancy can happen due:
    // - A new projection is added and starts from zero.
    // - A projection version changes and only that projection is rebuilt.
    // - An inconsistent projection is reset while stable projections retain their progress.
    final start = _projections
        .map((projection) => projection.position)
        .reduce((left, right) => left < right ? left : right);
    final reader = _createReader(start);
    var lastLocalSequence = start;

    while (await reader.loadMore()) {
      lastLocalSequence = _validateLocalSequences(
        reader.currentPage,
        lastLocalSequence,
      );
      final page = <DecodedLocalEvent>[
        for (final durableEvent in reader.currentPage)
          DecodedLocalEvent(
            durableEvent: durableEvent,
            event: _eventRegistry.decodeObject(durableEvent.encodedEvent),
          ),
      ];
      await _applyPage(page);
    }
  }

  int _validateLocalSequences(List<LocalEvent> page, int lastLocalSequence) {
    var position = lastLocalSequence;
    for (final event in page) {
      final expected = position + 1;
      if (event.localSequence != expected) {
        throw StateError(
          'Expected local sequence $expected, but found '
          '${event.localSequence}',
        );
      }
      position = event.localSequence;
    }
    return position;
  }

  Future<void> _applyPage(List<DecodedLocalEvent> page) async {
    _PageFailure? firstFailure;

    Future<void> apply(PreparedProjectionPageAdapter projection) async {
      try {
        await projection.applyPage(page);
      } catch (error, stackTrace) {
        firstFailure ??= _PageFailure(error, stackTrace);
      }
    }

    // Run all projections in parallel
    await Future.wait([
      for (final projection in _projections) apply(projection),
    ]);
    firstFailure?.rethrowNow();
  }
}

final class _PageFailure {
  final Object error;
  final StackTrace stackTrace;

  const _PageFailure(this.error, this.stackTrace);

  Never rethrowNow() => Error.throwWithStackTrace(error, stackTrace);
}
