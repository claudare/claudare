import 'dart:convert';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  test('command IDs reject malformed JSON length', () {
    expect(() => CommandId.fromJson(['alice']), throwsFormatException);
  });

  test('event IDs preserve the command ID and event index', () {
    final id = EventId('actor', 2, 3);
    expect(EventId.fromJson(id.toJson()), id);
    expect(id.commandId, const CommandId('actor', 2));
  });

  test('event IDs reject negative indexes', () {
    expect(() => EventId('actor', 1, -1), throwsFormatException);
  });

  test('event IDs reject malformed JSON length', () {
    expect(() => EventId.fromJson(['actor', 1]), throwsFormatException);
  });

  test('dependencies compare causal histories', () {
    final dependency = CommandDependency({'alice': 3, 'bob': 4});
    final frontier = CommandDependency({'alice': 3, 'bob': 5});
    expect(frontier.contains(dependency), isTrue);
    expect(dependency.contains(frontier), isFalse);
    expect(frontier.contains(CommandDependency({'unknown': 1})), isFalse);
    expect(frontier.value('unknown'), 0);
  });

  test('advance accepts only the next command for an actor', () {
    final dependency = CommandDependency({'alice': 3});
    expect(
      dependency.advance(const CommandId('alice', 4)),
      CommandDependency({'alice': 4}),
    );
    expect(dependency.value('alice'), 3);
    for (final sequence in [2, 3, 5]) {
      expect(
        () => dependency.advance(CommandId('alice', sequence)),
        throwsStateError,
      );
    }
  });

  test('dependencies round trip through JSON string keys', () {
    final dependency = CommandDependency({'bob': 2, '': 1, 'alice': 3});
    expect(
      CommandDependency.fromJson(
        jsonDecode(jsonEncode(dependency.toJson())) as Map<String, dynamic>,
      ),
      dependency,
    );
    expect(dependency.toJson().keys, ['', 'alice', 'bob']);
  });

  test('dependency equality and hashing ignore insertion order', () {
    final first = CommandDependency({'alice': 2, 'bob': 1});
    final second = CommandDependency({'bob': 1, 'alice': 2});
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect({first, second}, hasLength(1));
    expect(first, isNot(CommandDependency({'alice': 1, 'bob': 2})));
  });

  test('dependency constructor copies and freezes its input', () {
    final values = {'alice': 1};
    final dependency = CommandDependency(values);
    values['alice'] = 2;
    expect(dependency.value('alice'), 1);
    expect(() => dependency.values['alice'] = 3, throwsUnsupportedError);
  });

  test('zero sequences mean no dependency', () {
    expect(CommandDependency({'unknown': 0}), CommandDependency());
  });

  test('negative dependency sequences are rejected', () {
    expect(() => CommandDependency({'alice': -1}), throwsFormatException);
    expect(
      () => CommandDependency.fromJson({'alice': -1}),
      throwsFormatException,
    );
  });

  test('non-integer dependency sequences are rejected', () {
    expect(
      () => CommandDependency.fromJson({'alice': 1.5}),
      throwsA(isA<TypeError>()),
    );
  });

  test('builder retains the greatest sequence for each actor', () {
    final builder =
        CommandDependencyBuilder()
          ..apply(const CommandId('alice', 2))
          ..apply(const CommandId('bob', 3))
          ..apply(const CommandId('alice', 1))
          ..apply(const CommandId('alice', 2))
          ..apply(const CommandId('alice', 4));
    expect(builder.finish(), CommandDependency({'alice': 4, 'bob': 3}));
  });

  test('builder returns independent immutable snapshots', () {
    final builder =
        CommandDependencyBuilder()..apply(const CommandId('alice', 1));
    final snapshot = builder.finish();
    builder.apply(const CommandId('alice', 2));
    expect(snapshot, CommandDependency({'alice': 1}));
    expect(builder.finish(), CommandDependency({'alice': 2}));
  });
}
