import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  for (final kind in [
    'test',
    SystemEventKinds.streamDeleted,
    SystemEventKinds.eventErased,
  ]) {
    test('$kind survives command JSON serialization', () {
      final original = StoredCommand(
        commandId: const CommandId('actor', 1),
        dependency: CommandDependency(),
        occuredAt: DateTime.utc(2026),
        events: [
          StoredCommandEvent(
            streamPath: 'one',
            encodedEvent: EncodedEvent(
              kind: kind,
              bytes: kind == 'test' ? Uint8List.fromList([255]) : Uint8List(0),
            ),
            occuredAt: DateTime.utc(2026),
          ),
        ],
      );
      final json = original.toJson();
      final eventJson = (json['events'] as List).single as Map;
      expect(eventJson['kind'], kind);
      expect(eventJson['bytes'], kind == 'test' ? '/w==' : '');
      expect(eventJson.containsKey('kind'), isTrue);
      expect(eventJson.containsKey('bytes'), isTrue);
      final restored = StoredCommand.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(restored.toJson(), json);
      expect(restored.events.single.encodedEvent.kind, kind);
    });
  }

  StoredCommand command() => StoredCommand(
    commandId: const CommandId('writer/actor', 3),
    dependency: CommandDependency({'writer/actor': 2, 'peer': 4}),
    occuredAt: DateTime.utc(2026),
    events: [
      for (final (index, path) in ['one', 'two', 'one'].indexed)
        StoredCommandEvent(
          streamPath: path,
          encodedEvent: EncodedEvent(
            kind: 'event-$index',
            bytes: Uint8List.fromList([0, index, 255]),
          ),
          occuredAt: DateTime.utc(2026).add(Duration(milliseconds: index)),
        ),
    ],
  );

  test(
    'stored command JSON uses command IDs and string actor dependencies',
    () {
      final json = command().toJson();
      expect(json['commandId'], ['writer/actor', 3]);
      expect(json['dependency'], {'writer/actor': 2, 'peer': 4});
    },
  );

  test('stored command JSON preserves metadata and ordered events', () {
    final original = command();
    final restored = StoredCommand.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), original.toJson());
    expect(restored.commandId, original.commandId);
    expect(restored.dependency, original.dependency);
    expect(restored.events.map((event) => event.streamPath), [
      'one',
      'two',
      'one',
    ]);
    expect(restored.events.last.encodedEvent.bytes, [0, 2, 255]);
  });

  test('stored command rejects a stringified command ID', () {
    final json = command().toJson()..['commandId'] = 'writer,3';
    expect(() => StoredCommand.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('stored command rejects an invalid dependency value', () {
    final json = command().toJson()..['dependency'] = {'peer': -1};
    expect(() => StoredCommand.fromJson(json), throwsFormatException);
  });

  test('stored event rejects invalid payload encoding', () {
    final json = command().events.first.toJson()..['bytes'] = '!';
    expect(() => StoredCommandEvent.fromJson(json), throwsFormatException);
  });

  test('stored event rejects an unknown reserved kind', () {
    final json = command().events.first.toJson()..['kind'] = r'$unknown';
    expect(() => StoredCommandEvent.fromJson(json), throwsArgumentError);
  });

  test('string representations identify types without payload bytes', () {
    final original = command();
    expect(original.toString(), startsWith('StoredCommand('));
    expect(original.events.first.toString(), startsWith('StoredCommandEvent('));
    expect(original.events.first.toString(), contains('byteLength: 3'));
    expect(original.toString(), isNot(contains('AAD/')));
  });
}
