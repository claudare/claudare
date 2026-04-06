import 'package:core/cqrs.dart';

class CommandTesterStore {
  final List<FakeWrittenEvent> events = [];

  CommandTesterStore();

  void append<Event, Data>(
    String streamPath,
    EventCodec<Event> codec,
    Event event,
  ) {
    events.add(FakeWrittenEvent.withCodecPath(streamPath, codec, event));
  }

  void appendPathOnly<Event>(String streamPath, Event event) {
    events.add(FakeWrittenEvent.withoutCodec(streamPath, event));
  }

  Iterable<Event> getForPattern<Event>(StreamIdPattern pattern) {
    return events
        .where((e) => pattern.globsPathOnly(e._streamPath))
        .map((e) => e.event);
  }

  Iterable<Event> getOnPath<Event>(String path) {
    return events.where((e) => e._streamPath == path).map((e) => e.event);
  }
}

class FakeWrittenEvent<TEvent, TData> {
  late final TEvent? _event;
  late final EventCodec<TEvent>? _codec;
  late final EncodedEvent? _encodedEvent;
  late final String _streamPath;

  FakeWrittenEvent.withCodecPath(
    String streamPath,
    EventCodec<TEvent> codec,
    TEvent event,
  ) {
    _event = null;
    _codec = codec;
    _encodedEvent = codec.encode(event);
    _streamPath = streamPath;
  }

  FakeWrittenEvent.withCodec(
    StreamIdPattern streamIdPattern,
    TData streamData,
    EventCodec<TEvent> codec,
    TEvent event,
  ) {
    _event = null;
    _codec = codec;
    _encodedEvent = codec.encode(event);
    _streamPath = streamIdPattern.toPath(streamData);
  }

  FakeWrittenEvent.withoutCodec(String streamPath, TEvent event) {
    _event = event;
    _codec = null;
    _encodedEvent = null;
    _streamPath = streamPath;
  }

  TEvent? get event {
    if (_event != null) return _event;
    return _codec!.decode(_encodedEvent!);
  }
}
