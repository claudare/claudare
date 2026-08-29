import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/projection_page_adapter.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:cqrs/src/cqrs/exception/cqrs_projection_failure.dart';

typedef AppliedEventReaderFactory =
    PaginatedReader<LocalEvent> Function(int localSequenceCursor);

/// Applies committed events to prepared projections from their durable
/// positions.
///
/// Create one pump after preparing every projection and call [pump] whenever
/// durable history may have advanced. Callers do not pass events. Concurrent
/// calls share the active work and request another scan. Call [stop] before
/// replacing the prepared projections or closing their owner. Stopping lets an
/// active scan finish, suppresses its trailing scan, and permanently closes the
/// pump. Durable local sequences must be contiguous from the scan's starting
/// position.
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
  bool _closed = false;

  EventPump({
    required AppliedEventReaderFactory createReader,
    required EventRegistry eventRegistry,
    required List<PreparedProjectionPageAdapter> projections,
  }) : _createReader = createReader,
       _eventRegistry = eventRegistry,
       _projections = List.unmodifiable(projections);

  Future<void> pump() {
    if (_closed) return _active ?? Future<void>.value();

    _scanRequested = true;
    final active = _active;
    if (active != null) return active;

    final completer = Completer<void>();
    _active = completer.future;
    _drain(completer);
    return completer.future;
  }

  /// Permanently closes this pump after its active scan settles.
  ///
  /// A requested trailing scan is suppressed. Calls to [pump] and [stop] share
  /// the active future while it is pending and become no-ops after it settles.
  Future<void> stop() {
    _closed = true;
    _scanRequested = false;
    return _active ?? Future<void>.value();
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
      final failure = switch (error) {
        CqrsProjectionFailure() => error,
        _ => CqrsProjectionFailure([(error: error, stackTrace: stackTrace)]),
      };
      completer.completeError(failure, failure.stackTrace);
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
    final results = <Future<CqrsProjectionError?>>[];

    Future<CqrsProjectionError?> apply(
      PreparedProjectionPageAdapter projection,
    ) async {
      try {
        await projection.applyPage(page);
        return null;
      } catch (error, stackTrace) {
        return (error: error, stackTrace: stackTrace);
      }
    }

    for (final projection in _projections) {
      results.add(apply(projection));
    }
    final errors = (await Future.wait(results)).nonNulls.toList();
    if (errors.isNotEmpty) throw CqrsProjectionFailure(errors);
  }
}
