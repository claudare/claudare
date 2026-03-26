import 'dart:convert';

import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/metadata/metadata.dart';
import 'package:core/src/cqrs/projection/projection.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern_wildcard.dart';
import 'package:test/test.dart';

// TODO: make this financial example (lame, but understandable)

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

class _ExampleCommandInput {
  final int value;

  _ExampleCommandInput({required this.value});

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

    await streamSink.lockLatest();

    streamSink.append(_ExampleEventAdd(valueAdd: count), null);
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

class _ExampleProjection implements Projection {
  final _ExampleReadModelRepo _repo;

  _ExampleProjection(this._repo);

  @override
  Future<void> apply({
    required int version,
    required idData,
    required event,
    AnyMetadata? metadata,
  }) {
    // TODO: implement apply
    throw UnimplementedError();
  }

  @override
  // TODO: implement eventCodec
  EventCodec<dynamic> get eventCodec => throw UnimplementedError();

  @override
  Future<int> getSequenceNumber() {
    // TODO: implement getSequenceNumber
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  Future<void> reset() {
    // TODO: implement reset
    throw UnimplementedError();
  }

  @override
  // TODO: implement streamIdPattern
  StreamIdPattern<dynamic> get streamIdPattern => throw UnimplementedError();
}

// TODO: 2 examples, with methods from here https://event-driven.io/en/projections_and_read_models_in_event_driven_architecture/
// one with getAndStore, another with direct DB apply()
// this is a way to demo on how to use this and to test usage of all features!
void main() {
  group('CQRS Quick Example', () {
    test('standalone use', () async {
      final eventStore = MemoryEventStore(
        getTime: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      final executer = CommandExecutor(eventStore);

      final cmdDep = _ExampleDep();
      final cmd = _ExampleCommand(cmdDep);

      final res = await executer.executeThrowable(
        cmd,
        _ExampleCommandInput(value: 123),
      );
    });
  });
}
