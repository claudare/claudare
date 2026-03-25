import 'dart:convert';

import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executer.dart';
import 'package:core/src/cqrs/event/event_pack.dart';
import 'package:core/src/cqrs/event_store/event_store_memory.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern_wildcard.dart';
import 'package:test/test.dart';

sealed class _ExampleEvent {
  _ExampleEvent();
}

class _ExampleEventAdd extends _ExampleEvent {
  final int valueAdd;

  _ExampleEventAdd({required this.valueAdd});

  toJson() => {'value': valueAdd};

  factory _ExampleEventAdd.fromJson(Map<String, dynamic> json) =>
      _ExampleEventAdd(valueAdd: json['value'] as int);
}

class _ExampleEventSubtract extends _ExampleEvent {
  final int valueSub;

  _ExampleEventSubtract({required this.valueSub});

  toJson() => {'value': valueSub};

  factory _ExampleEventSubtract.fromJson(Map<String, dynamic> json) =>
      _ExampleEventSubtract(valueSub: json['value'] as int);
}

class _ExampleEventPack implements EventPack<_ExampleEvent> {
  const _ExampleEventPack();

  @override
  EncodedEvent encode(value) {
    switch (value) {
      case _ExampleEventAdd():
        return EncodedEvent(
          kind: 'exampleEvent1',
          detail: jsonEncode(value.toJson()),
        );
      case _ExampleEventSubtract():
        return EncodedEvent(
          kind: 'exampleEvent2',
          detail: jsonEncode(value.toJson()),
        );
    }
  }

  @override
  decode(EncodedEvent raw) {
    final map = jsonDecode(raw.detail);
    switch (raw.kind) {
      case 'exampleEvent1':
        return _ExampleEventAdd.fromJson(map);
      case 'exampleEvent2':
        return _ExampleEventSubtract.fromJson(map);
      default:
        throw Exception("unknown event kind");
    }
  }
}

final _exampleStreamId = StreamIdPatternWildcard("example/*");
// instance sshould be used
const _exampleEventPack = _ExampleEventPack();

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
      _exampleEventPack,
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

    final streamSink = ctx.stream(_exampleEventPack, _exampleStreamId, "sink");

    await streamSink.lock();

    streamSink.append(_ExampleEventAdd(valueAdd: count), null);
  }
}

void main() {
  group('CQRS Example', () {
    test('full usage', () async {
      final eventStore = EventStoreMemory(
        getTime: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      final executer = CommandExecuter(eventStore);

      final cmdDep = _ExampleDep();
      final cmd = _ExampleCommand(cmdDep);

      final res = await executer.executeThrowable(
        cmd,
        _ExampleCommandInput(value: 123),
      );
    });
  });
}
