import 'dart:convert';

import 'package:core/crdt.dart';
import 'package:core/src/crdt/common/logical_clock.dart';
import 'package:test/test.dart';

void main() {
  group('CrdtTextResolver', () {
    late CrdtTextResolver resolver;
    late VectorLogicalClock vectorClock;
    late LogicalClockGenerator aGen;

    setUp(() {
      resolver = CrdtTextResolver([]);
      vectorClock = VectorLogicalClock.empty();
      aGen = vectorClock.getGenerator(0);
    });

    test('ordered insertions', () {
      final a0 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, 'H'));
      resolver.handleOp(CrdtTextOpInsert(aGen.next(), a0, 'i'));

      final value = resolver.getTextContentLatest();
      expect(value, equals('Hi'));
    });

    test('unordered insertions', () {
      final a0 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, 'H')); // 0a

      final a1 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a1, a0, 'l'));

      final a2 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a2, a1, 'p'));

      // late insertion
      final a3 = aGen.next(); // 3a
      resolver.handleOp(CrdtTextOpInsert(a3, a0, 'e'));

      final value = resolver.getTextContentLatest();
      expect(value, equals('Help'));
    });

    test('deletions', () {
      final a0 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, 'H'));

      final a1 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a1, a0, 'u'));

      final a2 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a2, a1, 'i'));

      final a3 = aGen.next();
      resolver.handleOp(CrdtTextOpDelete(a3, a1)); // 3a

      final value = resolver.getTextContentLatest();
      expect(value, equals('Hi'));

      final atTimeValue = resolver.debugGetContentAtVector(
        VectorLogicalClock({0: 2}), // event 2a inclusive, pre-delete
      );
      expect(atTimeValue, equals('Hui'));
    });

    // aka edge-case 1 below
    test('edge case insertion (between two afterId nulls)', () {
      final a0 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, '2'));
      final a1 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a1, null, '1'));

      expect(resolver.getTextContentLatest(), equals('12'));

      final a2 = aGen.next();
      resolver.handleOp(CrdtTextOpInsert(a2, a1, '3'));

      // hmm, actual is 123
      expect(resolver.getTextContentLatest(), equals('132'));
    });

    // this test needs to be different
    // on it, there are multiple peers both get offline values
    test('handles concurrent edits', () {
      final aOffline = TestLogicalClockOffline.zero(0);
      final bOffline = TestLogicalClockOffline.zero(1);

      final a0 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, 'H'));

      final a1 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a1, a0, 'e'));

      final a2 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a2, a1, 'l'));

      final a3 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a3, a2, 'o'));

      aOffline.syncWithVectorClock(vectorClock);
      bOffline.syncWithVectorClock(vectorClock);

      final a4 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a4, a1, 'l'));

      final b4 = bOffline.next();
      resolver.handleOp(CrdtTextOpInsert(b4, a3, '!'));

      final value = resolver.getTextContentLatest();
      expect(value, equals('Hello!'));
    });

    test('handles concurrent edits to the start', () {
      final aOffline = TestLogicalClockOffline.zero(0);
      final bOffline = TestLogicalClockOffline.zero(1);

      final a0 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, 'y'));

      final a1 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a1, a0, 'e'));

      aOffline.syncWithVectorClock(vectorClock);
      bOffline.syncWithVectorClock(vectorClock);

      final b2 = bOffline.next();
      resolver.handleOp(CrdtTextOpInsert(b2, null, 'b'));

      final value = resolver.getTextContentLatest();
      expect(value, equals('bye'));
    });

    test('handles duplicate ops', () {
      final op1 = CrdtTextOpInsert(LogicalClock(0, 0), null, 'H');
      final op2 = CrdtTextOpInsert(LogicalClock(1, 0), LogicalClock(0, 0), 'i');
      final op3 = CrdtTextOpDelete(LogicalClock(2, 0), LogicalClock(1, 0));

      resolver.handleOp(op1);
      resolver.handleOp(op2);
      resolver.handleOp(op2);
      resolver.handleOp(op3);
      resolver.handleOp(op3);

      final value = resolver.getTextContentLatest();
      expect(value, equals('H'));
    });

    test('edge-case 1', () {
      final aOffline = TestLogicalClockOffline.zero(0);
      final bOffline = TestLogicalClockOffline.zero(1);

      final a0 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a0, null, 'a'));

      final a1 = aOffline.next();
      resolver.handleOp(CrdtTextOpInsert(a1, a0, 'b'));

      aOffline.syncWithVectorClock(vectorClock);
      bOffline.syncWithVectorClock(vectorClock);

      final b2 = bOffline.next();
      resolver.handleOp(CrdtTextOpInsert(b2, null, 'c'));

      // nasty edge case...
      final b3 = bOffline.next();
      resolver.handleOp(CrdtTextOpInsert(b3, b2, 'd'));

      final value = resolver.getTextContentLatest();
      expect(value, equals('cdab'));
    });

    test('returns a subset of latest content', () {
      // insert abc. delete b
      resolver.handleOp(CrdtTextOpInsert(LogicalClock(0, 0), null, 'a'));
      resolver.handleOp(
        CrdtTextOpInsert(LogicalClock(1, 0), LogicalClock(0, 0), 'b'),
      );
      resolver.handleOp(
        CrdtTextOpInsert(LogicalClock(2, 0), LogicalClock(1, 0), 'c'),
      );
      resolver.handleOp(
        CrdtTextOpDelete(LogicalClock(3, 0), LogicalClock(1, 0)),
      );

      final value = resolver.getTextContentLatest(maxLen: 1);
      expect(value, equals('a'));
    });

    test('serialization of changes', () {
      final original = CrdtTextChange(1000, [
        CrdtTextOpInsert(LogicalClock(0, 0), null, 'H'),
        CrdtTextOpInsert(LogicalClock(1, 0), LogicalClock(0, 0), 'i'),
      ]);

      final serialized = json.encode(original.toJson());
      // print('serialized: $serialized');

      final deserialized = CrdtTextChange.fromJson(json.decode(serialized));
      expect(
        deserialized.ops.first.toString(),
        equals(original.ops.first.toString()),
      );
      expect(original.ops.length, equals(deserialized.ops.length));
    });
  });

  group('CrdtText', () {
    late TestChangeFlusher changeFlusher;
    late CrdtText text;

    setUp(() {
      changeFlusher = TestChangeFlusher();

      // snapshot "Hello"
      final snapshot = CrdtTextSnapshot.evaluateVectorClock([
        CrdtTextRow(LogicalClock(0, 0), null, 'H', null),
        CrdtTextRow(LogicalClock(1, 0), LogicalClock(0, 0), 'e', null),
        CrdtTextRow(LogicalClock(2, 0), LogicalClock(1, 0), 'l', null),
        CrdtTextRow(LogicalClock(3, 0), LogicalClock(2, 0), 'l', null),
        CrdtTextRow(LogicalClock(4, 0), LogicalClock(3, 0), 'o', null),
      ]);

      text = CrdtText.fromSnapshot(
        0,
        changeFlusher.flushLocalChanges,
        snapshot,
      );
    });
    test('snapshot loads', () {
      expect(text.getContent(), equals('Hello'));
      expect(text.debugGetResolvedLength(), equals(5));
    });

    test('insertion at end', () {
      // cursor is at the start of the text
      text.moveCursor(5);
      text.insertAtCursor(' ');
      text.insertAtCursor('w');

      expect(text.getContent(), equals('Hello w'));
    });

    test('insertion at start', () {
      text.moveCursor(0);

      text.insertAtCursor('W');
      text.insertAtCursor('h');
      text.insertAtCursor('y');
      text.insertAtCursor(' ');

      expect(text.getContent(), equals('Why Hello'));
      expect(text.cursorIndex, equals(4));
    });
  });
}
