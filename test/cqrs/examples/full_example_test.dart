import 'dart:convert';

import 'package:core/src/cqrs/command/command_side_effects.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:core/src/cqrs/cqrs_runtime/cqrs_runtime.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/projection/projection.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern_wildcard.dart';
import 'package:test/test.dart';

// TODO: make this financial example (lame, but understandable)

sealed class _ExampleEvent {
  const _ExampleEvent();
}

class _ExampleEventAdd extends _ExampleEvent {
  static const String kind = 'exampleEvent1';

  final int valueAdd;

  const _ExampleEventAdd({required this.valueAdd});

  toJson() => {'valueAdd': valueAdd};

  factory _ExampleEventAdd.fromJson(Map<String, dynamic> json) =>
      _ExampleEventAdd(valueAdd: json['valueAdd'] as int);
}

class _ExampleEventSubtract extends _ExampleEvent {
  static const String kind = 'exampleEvent2';

  final int valueSub;

  const _ExampleEventSubtract({required this.valueSub});

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

class _ExampleCommandInput {
  final int value;

  const _ExampleCommandInput({required this.value});

  toJson() => {'value': value};

  factory _ExampleCommandInput.fromJson(Map<String, dynamic> json) =>
      _ExampleCommandInput(value: json['value'] as int);
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
  String get kind => 'exampleCommand';

  @override
  parseDetail(str) {
    return _ExampleCommandInput.fromJson(jsonDecode(str));
  }

  @override
  String encodeDetail(input) {
    return jsonEncode(input.toJson());
  }

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

    final iter = streamSource.iterator();

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

  const _ExampleProjection(this._repo);

  @override
  Future<void> apply(idData, event, metadata) {
    // TODO: implement apply
    throw UnimplementedError();
  }

  @override
  Future<int> getLocalSequence() {
    // TODO: implement getSequenceNumber
    throw UnimplementedError();
  }

  @override
  get name => "example";

  @override
  Future<void> reset() {
    // TODO: implement reset
    throw UnimplementedError();
  }

  @override
  get streamIdPattern => _exampleStreamId;

  @override
  get eventCodec => _exampleEventCodec;
}

// one way to make with type inference
final exampleProjection = createProjection(
  name: "example",
  streamIdPattern: _exampleStreamId,
  eventCodec: _exampleEventCodec,
  apply: (idData, event, metadata) async {
    //
  },
  reset: () async {},
  getLocalSequence: () async {
    return 0;
  },
);

// class _ExampleIdGenerator {
//   int i = 0;

//   String id() {
//     return (++i).toString();
//   }
// }

// actual implementaion

class _Commands {
  final BoundCommand<_ExampleCommandInput> example;

  const _Commands({required this.example});
}

class _ReadModels {
  /// TODO: this needs to be wrapped to not expose mutations, or 2 abstract classes
  final _ExampleReadModelRepo accounts;

  const _ReadModels({required this.accounts});
}

class _ExampleSideEffects implements CommandSideEffects {
  int _id = 0;

  @override
  DateTime currentTime() {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  @override
  String newId() {
    return (++_id).toString();
  }
}

class _ExampleCqrs {
  final EventStore _eventStore;

  late final CqrsRuntime _cqrsRuntime;
  late final _Commands command;
  late final _ReadModels readModel;

  _ExampleCqrs({
    required EventStore eventStore,
    required CommandSideEffects sideEffects,
    required DeviceId deviceId,
    required _ExampleReadModelRepo repo,
  }) : _eventStore = eventStore {
    final projection = _ExampleProjection(repo);

    _cqrsRuntime = CqrsRuntime(
      eventStore: _eventStore,
      projectors: [projection],
      sideEffects: sideEffects,
      deviceId: deviceId,
    );

    final dep = _ExampleDep();

    command = _Commands(
      example: _cqrsRuntime.bindCommand(_ExampleCommand(dep), [projection]),
    );

    readModel = _ReadModels(accounts: repo);
  }

  Future<void> init() async {
    await _cqrsRuntime.init();
  }
}

// TODO: 2 examples, with methods from here https://event-driven.io/en/projections_and_read_models_in_event_driven_architecture/
// one with getAndStore, another with direct DB apply()
// this is a way to demo on how to use this and to test usage of all features!
void main() {
  group('CqrsRuntime Example', () {
    test("runtime use", () async {
      final eventStore = MemoryEventStore(
        getTime: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      // final idGen = _ExampleIdGenerator();
      final deviceId = DeviceId(42);
      final sideEffects = _ExampleSideEffects();

      final someRepo = _ExampleReadModelRepo();

      final applicationCqrs = _ExampleCqrs(
        eventStore: eventStore,
        sideEffects: sideEffects,
        deviceId: deviceId,
        repo: someRepo,
      );
      await applicationCqrs.init();

      // call commands (Cqrs)
      await applicationCqrs.command.example.runThrowable(
        _ExampleCommandInput(value: 123),
      );

      // read the database (cQrs)
      final val = await applicationCqrs.readModel.accounts.getCount();
    });
  });
}
