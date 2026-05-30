import 'dart:convert';

import 'package:core/crdt.dart';
import 'package:core/src/crdt/common/logical_clock.dart';
import 'package:core/src/crdt/common/logical_clock_generator.dart';
import 'package:core/src/crdt/common/vector_logical_clock.dart';
import 'package:core/src/crdt/text/crdt_text_operation.dart';
import 'package:core/src/crdt/text/crdt_text_resolver.dart';
import 'package:core/src/crdt/text/crdt_text_row.dart';
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
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, 'H'));
      resolver.handleOperation(CrdtTextOperationInsert(aGen.next(), a0, 'i'));

      final value = resolver.resolveToStringSlow();
      expect(value, equals('Hi'));
    });

    test('unordered insertions', () {
      final a0 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, 'H'));

      final a1 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a1, a0, 'l'));

      final a2 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a2, a1, 'p'));

      expect(resolver.resolveToStringSlow(), equals('Hlp'));

      // late insertion
      final a3 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a3, a0, 'e'));

      expect(resolver.resolveToStringSlow(), equals('Help'));
    });

    test('deletions', () {
      final a0 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, 'H'));

      final a1 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a1, a0, 'u'));

      final a2 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a2, a1, 'i'));

      final a3 = aGen.next();
      resolver.handleOperation(CrdtTextOperationDelete(a3, a1)); // 3a

      final value = resolver.resolveToStringSlow();
      expect(value, equals('Hi'));

      final atTimeValue = resolver.debugGetContentAtVector(
        VectorLogicalClock({0: 2}), // event 2a inclusive, pre-delete
      );
      expect(atTimeValue, equals('Hui'));
    });

    // aka edge-case 1 below
    test('edge case insertion (between two afterId nulls)', () {
      final a0 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, '2'));
      final a1 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a1, null, '1'));

      expect(resolver.resolveToStringSlow(), equals('12'));

      final a2 = aGen.next();
      resolver.handleOperation(CrdtTextOperationInsert(a2, a1, '3'));

      // hmm, actual is 123
      expect(resolver.resolveToStringSlow(), equals('132'));
    });

    // this test needs to be different
    // on it, there are multiple peers both get offline values
    test('handles concurrent edits', () {
      final aOffline = TestLogicalClockOffline.zero(0);
      final bOffline = TestLogicalClockOffline.zero(1);

      final a0 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, 'H'));

      final a1 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a1, a0, 'e'));

      final a2 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a2, a1, 'l'));

      final a3 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a3, a2, 'o'));

      aOffline.syncWithVectorClock(vectorClock);
      bOffline.syncWithVectorClock(vectorClock);

      final a4 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a4, a1, 'l'));

      final b4 = bOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(b4, a3, '!'));

      final value = resolver.resolveToStringSlow();
      expect(value, equals('Hello!'));
    });

    test('handles concurrent edits to the start', () {
      final aOffline = TestLogicalClockOffline.zero(0);
      final bOffline = TestLogicalClockOffline.zero(1);

      final a0 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, 'y'));

      final a1 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a1, a0, 'e'));

      aOffline.syncWithVectorClock(vectorClock);
      bOffline.syncWithVectorClock(vectorClock);

      final b2 = bOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(b2, null, 'b'));

      final value = resolver.resolveToStringSlow();
      expect(value, equals('bye'));
    });

    test('handles duplicate ops', () {
      final op1 = CrdtTextOperationInsert(
        LogicalClock(counter: 0, actor: 0),
        null,
        'H',
      );
      final op2 = CrdtTextOperationInsert(
        LogicalClock(counter: 1, actor: 0),
        LogicalClock(counter: 0, actor: 0),
        'i',
      );
      final op3 = CrdtTextOperationDelete(
        LogicalClock(counter: 2, actor: 0),
        LogicalClock(counter: 1, actor: 0),
      );

      resolver.handleOperation(op1);
      resolver.handleOperation(op2);
      resolver.handleOperation(op2);
      resolver.handleOperation(op3);
      resolver.handleOperation(op3);

      final value = resolver.resolveToStringSlow();
      expect(value, equals('H'));
    });

    test('edge-case 1', () {
      final aOffline = TestLogicalClockOffline.zero(0);
      final bOffline = TestLogicalClockOffline.zero(1);

      final a0 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a0, null, 'a'));

      final a1 = aOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(a1, a0, 'b'));

      aOffline.syncWithVectorClock(vectorClock);
      bOffline.syncWithVectorClock(vectorClock);

      final b2 = bOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(b2, null, 'c'));

      // nasty edge case...
      final b3 = bOffline.next();
      resolver.handleOperation(CrdtTextOperationInsert(b3, b2, 'd'));

      expect(resolver.resolveToStringSlow(), equals('cdab'));
    });

    test('serialization of changes', () {
      final original = CrdtTextChange([
        CrdtTextOperationInsert(LogicalClock(counter: 0, actor: 0), null, 'H'),
        CrdtTextOperationInsert(
          LogicalClock(counter: 1, actor: 0),
          LogicalClock(counter: 0, actor: 0),
          'i',
        ),
      ]);

      final serialized = json.encode(original.toJson());
      // print('serialized: $serialized');

      final deserialized = CrdtTextChange.fromJson(json.decode(serialized));
      expect(
        deserialized.operations.first.toString(),
        equals(original.operations.first.toString()),
      );
      expect(
        original.operations.length,
        equals(deserialized.operations.length),
      );
    });
  });

  group('CrdtText', () {
    late TestChangeFlusher changeFlusher;
    late CrdtText text;

    setUp(() {
      changeFlusher = TestChangeFlusher();

      // snapshot "Hello"
      final snapshot = CrdtTextSnapshot.withoutVectorClock([
        CrdtTextRow(LogicalClock(counter: 0, actor: 0), null, 'H', null),
        CrdtTextRow(
          LogicalClock(counter: 1, actor: 0),
          LogicalClock(counter: 0, actor: 0),
          'e',
          null,
        ),
        CrdtTextRow(
          LogicalClock(counter: 2, actor: 0),
          LogicalClock(counter: 1, actor: 0),
          'l',
          null,
        ),
        CrdtTextRow(
          LogicalClock(counter: 3, actor: 0),
          LogicalClock(counter: 2, actor: 0),
          'l',
          null,
        ),
        CrdtTextRow(
          LogicalClock(counter: 4, actor: 0),
          LogicalClock(counter: 3, actor: 1),
          'o',
          null,
        ),
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
