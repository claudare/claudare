import 'package:crdt/crdt_string.dart';
import 'package:test/test.dart';

void main() {
  test('initializes empty', () {
    final crdt = CrdtString();

    expect(crdt.value, '');
  });

  test('applies a change', () {
    final crdt = CrdtString();

    crdt.applyChange(
      CrdtStringChange(value: 'hi', actor: 'a', time: DateTime.utc(0)),
    );

    expect(crdt.value, 'hi');
  });

  test('keeps value with a newer timestamp', () {
    final crdt = CrdtString();

    crdt.applyChange(
      CrdtStringChange(value: 'newer', actor: 'a', time: DateTime.utc(2026)),
    );
    crdt.applyChange(
      CrdtStringChange(value: 'older', actor: 'a', time: DateTime.utc(2000)),
    );

    expect(crdt.value, 'newer');
  });

  test('updates value with older timestamp', () {
    final crdt = CrdtString();

    crdt.applyChange(
      CrdtStringChange(value: 'older', actor: 'a', time: DateTime.utc(2000)),
    );
    crdt.applyChange(
      CrdtStringChange(value: 'newer', actor: 'a', time: DateTime.utc(2026)),
    );

    expect(crdt.value, 'newer');
  });

  test('handles tie breakers', () {
    final crdt = CrdtString();

    crdt.applyChange(
      CrdtStringChange(value: 'alice', actor: 'a', time: DateTime.utc(0)),
    );
    crdt.applyChange(
      CrdtStringChange(value: 'bob', actor: 'b', time: DateTime.utc(0)),
    );
    crdt.applyChange(
      CrdtStringChange(value: 'alice', actor: 'a', time: DateTime.utc(0)),
    );

    expect(crdt.value, 'bob');
  });

  test('handles rare self-tie-breaker', () {
    final crdt = CrdtString();

    crdt.applyChange(
      CrdtStringChange(value: 'hello', actor: 'a', time: DateTime.utc(0)),
    );
    crdt.applyChange(
      CrdtStringChange(value: 'hello1', actor: 'a', time: DateTime.utc(0)),
    );
    crdt.applyChange(
      CrdtStringChange(value: 'hello0', actor: 'a', time: DateTime.utc(0)),
    );

    expect(crdt.value, 'hello1');
  });

  test('restores the winning value and tie breakers from JSON', () {
    final original = CrdtString()
      ..applyChange(
        CrdtStringChange(value: 'winner', actor: 'b', time: DateTime.utc(2026)),
      );
    final restored = CrdtString.fromJson(original.toJson());

    restored.applyChange(
      CrdtStringChange(value: 'loser', actor: 'a', time: DateTime.utc(2026)),
    );

    expect(restored.value, 'winner');
    expect(restored.toJson(), original.toJson());
  });
}
