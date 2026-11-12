import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';

final projectionTime = DateTime.utc(2026);

class CallSignal {
  int count = 0;
  final _waiters = <int, Completer<void>>{};

  Future<void> waitFor(int count) => this.count >= count
      ? Future<void>.value()
      : (_waiters[count] ??= Completer<void>()).future;

  void record() {
    count++;
    for (final target in _waiters.keys.toList()) {
      if (target <= count) _waiters.remove(target)!.complete();
    }
  }
}

class AsyncGate {
  final entered = Completer<void>();
  final _released = Completer<void>();

  Future<void> wait() {
    if (!entered.isCompleted) entered.complete();
    return _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class ProjectionEvent {
  final String value;

  const ProjectionEvent(this.value);
}

class ProjectionEventCodec implements EventCodec<ProjectionEvent> {
  const ProjectionEventCodec();

  @override
  String get kind => 'projection-event';

  @override
  ProjectionEvent fromBytes(Uint8List bytes) =>
      ProjectionEvent(utf8.decode(bytes));

  @override
  Uint8List toBytes(ProjectionEvent event) =>
      Uint8List.fromList(utf8.encode(event.value));
}

class ControlledMemoryEventStore extends MemoryEventStore {
  late final StreamController<EventChange> _changes;
  late final StreamSubscription<EventChange> _forwarding;
  Future<void>? _closeFuture;
  final subscriptions = CallSignal();
  final cancellations = CallSignal();
  final notifications = CallSignal();
  final reads = CallSignal();
  final emptyReads = CallSignal();
  final positions = <int>[];
  Future<void> Function(PaginatedResult<StoredEvent> page)? afterRead;

  ControlledMemoryEventStore() : super(eventFetchPageSize: 1) {
    _changes = StreamController<EventChange>.broadcast(
      onListen: subscriptions.record,
      onCancel: cancellations.record,
    );
    _forwarding = super.eventChanges.listen((change) {
      _changes.add(change);
      notifications.record();
    });
  }

  @override
  Stream<EventChange> get eventChanges => _changes.stream;

  bool get hasChangeListener => _changes.hasListener;

  void pauseNotifications() => _forwarding.pause();

  void notify(String path) => _changes.add(EventChange(stream: path));

  void failNotifications(Object error, StackTrace stackTrace) =>
      _changes.addError(error, stackTrace);

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  ) async {
    positions.add(fromPosition);
    reads.record();
    final page = await super.getLogEvents(filter, fromPosition);
    await afterRead?.call(page);
    if (page.data.isEmpty) emptyReads.record();
    return page;
  }

  Future<void> closeChanges() => _closeFuture ??= () async {
    await _forwarding.cancel();
    await _changes.close();
  }();
}

Future<void> appendProjectionEvent(
  EventStore store,
  String value, {
  String path = 'notes/one',
  String actor = 'actor',
  DateTime? occuredAt,
  EncodedEvent? encodedEvent,
}) async {
  final state = await store.getState();
  final sequence = state.logVersion.value(actor) + 1;
  final time = occuredAt ?? projectionTime;
  final accepted = await store.addStoredCommand(
    StoredCommand(
      commandId: CommandId(actor, sequence),
      dependency: state.logVersion,
      occuredAt: time,
      events: [
        StoredCommandEvent(
          streamPath: path,
          encodedEvent:
              encodedEvent ??
              EncodedEvent(
                kind: 'projection-event',
                bytes: const ProjectionEventCodec().toBytes(
                  ProjectionEvent(value),
                ),
              ),
          occuredAt: time,
        ),
      ],
    ),
  );
  if (!accepted) throw StateError('Test command was rejected');
}
