import 'dart:convert';

import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs_test_utils.dart';
import 'package:test/test.dart';

sealed class _ExampleEvent {
  _ExampleEvent();
}

class _ExampleEventAdd extends _ExampleEvent {
  static const String kind = 'exampleEvent1';

  final int valueAdd;

  _ExampleEventAdd({required this.valueAdd});

  toJson() => {'valueAdd': valueAdd};

  factory _ExampleEventAdd.fromJson(Map<String, dynamic> json) =>
      _ExampleEventAdd(valueAdd: json['valueAdd'] as int);
}

class _ExampleEventSubtract extends _ExampleEvent {
  static const String kind = 'exampleEvent2';

  final int valueSub;

  _ExampleEventSubtract({required this.valueSub});

  toJson() => {'valueSub': valueSub};

  factory _ExampleEventSubtract.fromJson(Map<String, dynamic> json) =>
      _ExampleEventSubtract(valueSub: json['valueSub'] as int);
}

class _ExampleEventCodec implements EventCodec<_ExampleEvent> {
  const _ExampleEventCodec();

  @override
  encode(value) {
    switch (value) {
      case _ExampleEventAdd():
        return EncodedEvent(
          kind: _ExampleEventAdd.kind,
          detail: jsonEncode(value.toJson()),
        );
      case _ExampleEventSubtract():
        return EncodedEvent(
          kind: _ExampleEventSubtract.kind,
          detail: jsonEncode(value.toJson()),
        );
    }
  }

  @override
  decode(raw) {
    final map = jsonDecode(raw.detail);
    switch (raw.kind) {
      case _ExampleEventAdd.kind:
        return _ExampleEventAdd.fromJson(map);
      case _ExampleEventSubtract.kind:
        return _ExampleEventSubtract.fromJson(map);
      default:
        throw Exception("unknown event kind");
    }
  }
}

final _exampleStreamId = StreamIdPatternWildcard("example/*");
// instance sshould be used
const _exampleEventCodec = _ExampleEventCodec();

class _ExampleCommandInput implements CommandInput {
  final int value;

  _ExampleCommandInput({required this.value});

  @override
  String get kind => 'exampleCommand';

  @override
  toJson() => {'value': value};
}

class _ExampleDep {
  log(String message) {
    print("DEPENDENCY LOG: $message");
  }
}

class _ExampleCommand implements Command<_ExampleCommandInput> {
  final _ExampleDep dep;

  const _ExampleCommand(this.dep);

  @override
  Future<void> handle(input, ctx) async {
    if (input.value > 9000) {
      ctx.nack("value is over 9000");
      return;
    }

    final streamSource = ctx.stream(
      _exampleEventCodec,
      _exampleStreamId,
      "source",
    );

    final iter = streamSource.scan();

    var count = 0;

    await for (final event in iter) {
      switch (event) {
        case _ExampleEventAdd():
          count += event.valueAdd;
          break;
        case _ExampleEventSubtract():
          count -= event.valueSub;
          break;
      }
    }

    final streamSink = ctx.stream(_exampleEventCodec, _exampleStreamId, "sink");

    await streamSink.lock();

    streamSink.append(_ExampleEventAdd(valueAdd: count));
  }
}

class _ExampleReadModelRepo {
  Future<int> getCount() async {
    return -1;
  }

  Future<void> setCount(int count) async {
    return;
  }
}

class _ExampleProjection implements Projection<_ExampleEvent, String> {
  final _ExampleReadModelRepo _repo;

  _ExampleProjection(this._repo);

  @override
  // TODO: implement name
  String get name => "example";

  @override
  get eventCodec => _exampleEventCodec;

  @override
  get streamIdPattern => _exampleStreamId;

  @override
  Future<ProjectionCheckpoint> checkpoint() {
    // TODO: implement getSequenceNumber
    throw UnimplementedError();
  }

  @override
  Future<void> reset() {
    // TODO: implement reset
    throw UnimplementedError();
  }

  @override
  Future<void> apply(id, event, meta) {
    // TODO: implement apply
    throw UnimplementedError();
  }
}

// TODO: 2 examples, with methods from here https://event-driven.io/en/projections_and_read_models_in_event_driven_architecture/
// one with getAndStore, another with direct DB apply()
// this is a way to demo on how to use this and to test usage of all features!
void main() {
  group('CQRS Quick Example', () {
    test('standalone use', () async {
      final eventStore = MemoryEventStore(
        timeProvider: FakeTimeProviderStatic.zero(),
      );
      final deviceId = DeviceId(41);

      final executer = CommandExecutor(
        eventStore: eventStore,
        idGenerator: FakeIdGeneratorSequential(),
        timeProvider: FakeTimeProviderStatic.zero(),
        thisDeviceId: deviceId,
        applicationId: "test",
        pageSize: 10,
      );

      final cmdDep = _ExampleDep();
      final cmd = _ExampleCommand(cmdDep);

      final res = await executer.executeThrowable(
        cmd,
        _ExampleCommandInput(value: 123),
      );
    });
  });
}
