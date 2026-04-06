import 'package:core/cqrs.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs_test_utils/command_tester/command_tester_store.dart';
import 'package:core/src/cqrs_test_utils/command_tester/test_command_stream.dart';
import 'package:core/src/id_generator/id_generator.dart';
import 'package:core/time_provider.dart';

class TestCommandContext implements CommandContext {
  final CommandTesterStore _readStore;
  final CommandTesterStore _writeStore;
  final CommandNacker _nacker;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  const TestCommandContext(
    this._readStore,
    this._writeStore,
    this._nacker,
    this._timeProvider,
    this._idGenerator,
  );

  @override
  void nack(String message) {
    _nacker.nack(message);
  }

  @override
  CommandStream<Event, IdData> stream<Event, IdData>(
    EventCodec<Event> eventCodec,
    StreamIdPattern<IdData> streamIdPattern,
    IdData streamData,
  ) {
    final streamPath = streamIdPattern.toPath(streamData);

    return TestCommandStream(streamPath, eventCodec, _readStore, _writeStore);
  }

  @override
  String newId() {
    return _idGenerator.generateId();
  }

  @override
  DateTime currentTime() {
    return _timeProvider.now();
  }
}
