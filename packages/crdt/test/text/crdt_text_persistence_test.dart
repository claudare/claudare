import 'package:crdt/crdt.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  group('save lifecycle', () {
    test('prepares the same batch until acknowledgment', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a');
      final first = text.prepareChange()!;
      text.insert(1, 'b');
      expect(text.prepareChange(), same(first));
      expect(first.operations, hasLength(1));
      text.acknowledgeChange(first);
      expect(text.prepareChange()!.operations, hasLength(1));
      expect(
        (text.prepareChange()!.operations.single as CrdtTextInsert).character,
        'b',
      );
    });

    test(
      'a failed persistence attempt leaves the batch available for retry',
      () async {
        final text = CrdtText(actorId: 'A')..insert(0, 'draft');
        final batch = text.prepareChange()!;
        final before = text.toJson();
        Future<void> persist(CrdtTextChange change) async {
          throw const FormatException('Storage rejected the write.');
        }

        await expectLater(persist(batch), throwsFormatException);
        expect(text.toJson(), before);
        expect(text.prepareChange(), same(batch));
      },
    );

    test(
      'acknowledgment clears only local edits and creates no text notification',
      () {
        final text = CrdtText(actorId: 'A')..insert(0, 'a');
        var notified = false;
        text.addListener(() => notified = true);
        text.acknowledgeChange(text.prepareChange()!);
        expect(text.hasPendingChanges, isFalse);
        expect(text.prepareChange(), isNull);
        expect(notified, isFalse);
      },
    );

    test('rejects an acknowledgment before preparation', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a');
      final candidate = CrdtTextChange([insertion(1, character: 'a')]);
      final before = text.toJson();
      expect(() => text.acknowledgeChange(candidate), throwsArgumentError);
      expect(text.toJson(), before);
    });

    test('rejects stale acknowledgments without discarding later edits', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a');
      final first = save(text);
      text.insert(1, 'b');
      text.prepareChange();
      final before = text.toJson();
      expect(() => text.acknowledgeChange(first), throwsArgumentError);
      expect(text.toJson(), before);
    });

    test('captures local edits on both sides of a remote change', () {
      final a = CrdtText(actorId: 'A')..insert(0, 'a');
      final b = CrdtText(actorId: 'B')..insert(0, 'b');
      final remote = save(b);
      a.applyChange(remote);
      a.insert(a.length, '!');
      final local = save(a);
      expect(
        local.operations.map((operation) => operation.id.actorId),
        everyElement('A'),
      );

      final receiver = CrdtText(actorId: 'C');
      expect(
        () => receiver.applyChange(local),
        throwsA(isA<CrdtTextException>()),
      );
      expect(receiver.text, '');
      receiver.applyChange(remote);
      receiver.applyChange(local);
      expect(receiver.text, a.text);
      expect(receiver.text, 'ba!');
    });

    test('allows remote replies to a prepared batch before acknowledgment', () {
      final a = CrdtText(actorId: 'A')..insert(0, 'a');
      final prepared = a.prepareChange()!;
      final b = CrdtText(actorId: 'B')..applyChange(prepared);
      b.insert(1, 'b');
      final reply = save(b);
      a.applyChange(reply);
      a.insert(2, 'c');
      a.acknowledgeChange(prepared);
      final later = save(a);
      b.applyChange(later);
      expect(b.text, 'abc');
      expect(a.text, b.text);
    });

    test('rejects another writer extending the local actor while dirty', () {
      final a = CrdtText(actorId: 'A')..insert(0, 'a');
      final other = CrdtText(actorId: 'A')..applyChange(a.prepareChange()!);
      other.insert(1, 'b');
      final before = a.toJson();
      expect(
        () => a.applyChange(save(other)),
        throwsA(isA<CrdtTextException>()),
      );
      expect(a.toJson(), before);
    });
  });

  group('JSON persistence', () {
    test('empty state round trips', () {
      final text = CrdtText(actorId: 'A');
      final restored = CrdtText.fromJson(jsonCopy(text.toJson()));
      expect(restored.toJson(), text.toJson());
    });

    test('restores tombstones and permits later insertion after them', () {
      final a = CrdtText(actorId: 'A')..insert(0, 'abc');
      final initial = save(a);
      final b = CrdtText(actorId: 'B')..applyChange(initial);
      a.delete(1, 2);
      save(a);
      b.insert(2, 'X');
      final restored = CrdtText.fromJson(jsonCopy(a.toJson()));
      restored.applyChange(save(b));
      expect(restored.text, 'aXc');
      expect(restored.hasPendingChanges, isFalse);
    });

    test('restores an outstanding save and edits made after preparation', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a😀');
      final first = text.prepareChange()!;
      text.insert(text.length, 'b');
      final snapshot = jsonCopy(text.toJson());
      final restored = CrdtText.fromJson(snapshot);
      expect(restored.actorId, 'A');
      expect(restored.prepareChange(), first);
      restored.acknowledgeChange(first);
      final later = restored.prepareChange()!;
      expect(later.operations, hasLength(1));
      expect((later.operations.single as CrdtTextInsert).character, 'b');
      restored.acknowledgeChange(later);
      restored.insert(restored.length, '!');
      expect(restored.prepareChange()!.operations.single.id.counter, 4);
      expect(restored.text, 'a😀b!');
      expect(text.toJson(), snapshot);
    });

    test('snapshot export does not prepare or acknowledge edits', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a');
      final snapshot = text.toJson();
      text.insert(1, 'b');
      expect(snapshot['prepared'], isNull);
      expect(text.prepareChange()!.operations, hasLength(2));
    });

    test('change JSON round trips insertions and deletions', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'x😀');
      text.delete(0, 1);
      final change = text.prepareChange()!;
      final restored = CrdtTextChange.fromJson(jsonCopy(change.toJson()));
      expect(restored, change);
      expect(restored.hashCode, change.hashCode);
      final replica = CrdtText(actorId: 'B')..applyChange(restored);
      expect(replica.text, '😀');
    });

    test('restored state detects a conflicting duplicate', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a');
      save(text);
      final restored = CrdtText.fromJson(jsonCopy(text.toJson()));
      expect(
        () => restored.applyChange(
          CrdtTextChange([insertion(1, character: 'b')]),
        ),
        throwsA(isA<CrdtTextException>()),
      );
    });

    test('operations and batches take immutable copies of their inputs', () {
      final context = <String, int>{};
      final operation = insertion(1, dependencies: context);
      final operations = <CrdtTextOperation>[operation];
      final change = CrdtTextChange(operations);
      context['B'] = 5;
      operations.clear();
      expect(change.operations, [operation]);
      expect(operation.dependencies, isEmpty);
      expect(() => change.operations.clear(), throwsUnsupportedError);
      expect(() => operation.dependencies['B'] = 5, throwsUnsupportedError);
    });

    test('mutating exported JSON cannot mutate the document', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a');
      final before = text.toJson();
      final json = text.toJson();
      ((json['operations'] as List).first as Map)['character'] = 'b';
      (json['pending'] as List).clear();
      expect(text.toJson(), before);
    });

    final corruptions = <(String, void Function(Map<String, Object?>))>[
      ('unknown version', (json) => json['version'] = 2),
      ('noninteger version', (json) => json['version'] = 1.0),
      ('empty actor', (json) => json['actorId'] = ''),
      ('missing operations', (json) => json.remove('operations')),
      (
        'duplicate operation',
        (json) {
          final operations = json['operations'] as List;
          operations.add(operations.first);
        },
      ),
      (
        'unknown operation kind',
        (json) {
          ((json['operations'] as List).first as Map)['kind'] = 'other';
        },
      ),
      (
        'invalid scalar',
        (json) {
          ((json['operations'] as List).first as Map)['character'] = 'ab';
        },
      ),
      (
        'noninteger counter',
        (json) {
          (((json['operations'] as List).first as Map)['id']
                  as Map)['counter'] =
              1.5;
        },
      ),
      (
        'missing causal predecessor',
        (json) {
          (json['operations'] as List).removeAt(0);
        },
      ),
      (
        'pending prefix instead of suffix',
        (json) {
          (json['pending'] as List).removeLast();
        },
      ),
      ('missing prepared state', (json) => json.remove('prepared')),
      (
        'prepared mismatch',
        (json) {
          json['prepared'] = CrdtTextChange([
            insertion(1, character: 'z'),
          ]).toJson();
        },
      ),
    ];
    for (final (name, corrupt) in corruptions) {
      test('rejects snapshot with $name', () {
        final text = CrdtText(actorId: 'A')..insert(0, 'ab');
        final json = jsonCopy(text.toJson());
        corrupt(json);
        expect(() => CrdtText.fromJson(json), throwsFormatException);
      });
    }

    for (final json in [
      null,
      [],
      {},
      {'version': 1, 'operations': []},
    ]) {
      test('rejects malformed change $json', () {
        expect(() => CrdtTextChange.fromJson(json), throwsFormatException);
      });
    }
  });
}
