import 'package:core/cqrs.dart';
import 'package:core/src/device_id.dart';
import 'package:core/time_provider.dart';

// A way to test the event store?
// TODO: This is probably not needed, remove this
class FakeEventStore {
  final _timeProvider = FakeTimeProviderStatic(
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  late final MemoryEventStore eventStore;

  FakeEventStore() {
    eventStore = MemoryEventStore();
  }

  FakeEventStore insertEvent(MemoryEventInsert raw) {
    eventStore.testInsertEvent(raw);
    return this;
  }

  FakeEventStore insertEventTyped<Event>({
    required String streamPath,
    required EventCodec<Event> codec,
    required Event event,
    // extra metadata, usually not needed
    DeviceId? deviceId,
    DateTime? occuredAt,
  }) {
    final deviceIdToUse = deviceId ?? DeviceId.unassigned();

    final encoded = codec.encode(event);

    final raw = MemoryEventInsert(
      deviceId: deviceIdToUse,
      streamId: streamPath,
      kind: encoded.kind,
      detail: encoded.detail,
      streamVersion: null,
      occuredAt: occuredAt ?? _timeProvider.now(),
    );

    return insertEvent(raw);
  }

  FakeEventStore insertEventStreamTyped<Event, StreamIdData>({
    required StreamIdPattern<StreamIdData> streamId,
    required StreamIdData streamIdData,
    required EventCodec<Event> codec,
    required Event event,
    // extra metadata, usually not needed
    DeviceId? deviceId,
    DateTime? occuredAt,
  }) {
    return insertEventTyped(
      streamPath: streamId.toPath(streamIdData),
      codec: codec,
      event: event,
      deviceId: deviceId,
      occuredAt: occuredAt,
    );
  }
}
