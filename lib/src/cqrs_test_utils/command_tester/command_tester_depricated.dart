import 'package:core/cqrs.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs_test_utils/command_tester/command_tester_store.dart';
import 'package:core/src/cqrs_test_utils/command_tester/test_command_context.dart';
import 'package:core/src/id_generator/id_generator.dart';
import 'package:core/time_provider.dart';

@Deprecated('use other command tester')
class CommandTesterDepricated<Input extends CommandInput> {
  final Command<Input> _command;
  final _nacker = CommandNacker();
  final _readStore = CommandTesterStore();
  final _writeStore = CommandTesterStore();
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  Object? _error;

  CommandTesterDepricated(
    this._command, {
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
  }) : _timeProvider = timeProvider,
       _idGenerator = idGenerator;

  // testing functions
  String? get nackMessage => _nacker.message;
  Object? get error => _error;

  // pre-append helpers.

  /// Appends event to the stream with type safety for stream and event.
  /// This is recommended as event pack encode/decode will be tested.
  CommandTesterDepricated<Input> withTypedStreamEvent<Event, IdData>(
    StreamIdPattern<IdData> streamIdPattern,
    IdData streamData,
    EventCodec<Event> eventCodec,
    Event event,
  ) {
    final streamPath = streamIdPattern.toPath(streamData);
    _readStore.append(streamPath, eventCodec, event);
    return this;
  }

  /// [withTypedStreamEvents] inserts multiple events with [withTypedStreamEvent].
  CommandTesterDepricated<Input> withTypedStreamEvents<Event, IdData>(
    StreamIdPattern<IdData> streamIdPattern,
    IdData streamData,
    EventCodec<Event> eventCodec,
    List<Event> events,
  ) {
    final streamPath = streamIdPattern.toPath(streamData);
    for (final event in events) {
      _readStore.append(streamPath, eventCodec, event);
    }
    return this;
  }

  /// Appends event to the stream with type safety for event only.
  /// This is recommended as event pack encode/decode will be tested.
  CommandTesterDepricated<Input> withTypedEvent<Event, IdData>(
    String streamPath,
    EventCodec<Event> eventCodec,
    Event event,
  ) {
    _readStore.append(streamPath, eventCodec, event);
    return this;
  }

  /// [withTypedEvents] inserts multiple events with [withTypedEvent].
  CommandTesterDepricated<Input> withTypedEvents<Event, IdData>(
    String streamPath,
    EventCodec<Event> eventCodec,
    List<Event> events,
  ) {
    for (final event in events) {
      _readStore.append(streamPath, eventCodec, event);
    }
    return this;
  }

  /// Appends event to the stream by path and runtime value.
  /// Warning: the event pack encode/decode will not be tested!
  CommandTesterDepricated<Input> withEvent<Event>(
    String streamPath,
    Event event,
  ) {
    _readStore.appendPathOnly(streamPath, event);
    return this;
  }

  /// [withEvents] inserts multiple events with [withEvent].
  CommandTesterDepricated<Input> withEvents<Event>(
    String streamPath,
    List<Event> events,
  ) {
    for (final event in events) {
      _readStore.appendPathOnly(streamPath, event);
    }
    return this;
  }

  // post test helpers

  Iterable<Event> getWrittenEventsForPattern<Event>(StreamIdPattern pattern) {
    return _writeStore.getForPattern<Event>(pattern);
  }

  Iterable<Event> getWrittenEventsOnPath<Event>(String path) {
    return _writeStore.getOnPath<Event>(path);
  }

  /// Returns true on succeess, false on failure.
  /// If failure is encountered, check [nackMessage] and [error].
  Future<bool> run(Input input) async {
    final ctx = TestCommandContext(
      _readStore,
      _writeStore,
      _nacker,
      _timeProvider,
      _idGenerator,
    );
    try {
      await _command.handle(input, ctx);
      if (_nacker.message != null) {
        throw CommandNack(message: _nacker.message!);
      }
      return true;
    } catch (e) {
      if (e is CommandNack) {
        return false;
      }

      _error = e;

      return false;
    }
  }
}
