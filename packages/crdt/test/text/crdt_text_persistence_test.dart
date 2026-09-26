import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  group('save lifecycle', () {
    test('prepares the same batch until acknowledgment', () {
      final text = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
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
        final text = CrdtTextTestUtils.editContext('A')..insert(0, 'draft');
        final batch = text.prepareChange()!;
        Future<void> persist(CrdtTextChange change) async {
          throw const FormatException('Storage rejected the write.');
        }

        await expectLater(persist(batch), throwsFormatException);
        expect(text.text, 'draft');
        expect(text.hasPendingChanges, isTrue);
        expect(text.prepareChange(), same(batch));
      },
    );

    test(
      'acknowledgment clears only local edits and creates no text notification',
      () {
        final text = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
        var notified = false;
        text.addListener(() => notified = true);
        text.acknowledgeChange(text.prepareChange()!);
        expect(text.hasPendingChanges, isFalse);
        expect(text.prepareChange(), isNull);
        expect(notified, isFalse);
      },
    );

    test('rejects an acknowledgment before preparation', () {
      final text = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
      final candidate = CrdtTextChange([insertion(1, character: 'a')]);
      expect(() => text.acknowledgeChange(candidate), throwsArgumentError);
      expect(text.text, 'a');
      expect(text.prepareChange(), candidate);
    });

    test('rejects stale acknowledgments without discarding later edits', () {
      final text = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
      final first = CrdtTextTestUtils.save(text);
      text.insert(1, 'b');
      final before = text.prepareChange();
      expect(() => text.acknowledgeChange(first), throwsArgumentError);
      expect(text.prepareChange(), same(before));
      expect(text.text, 'ab');
    });

    test('captures local edits on both sides of a remote change', () {
      final a = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
      final b = CrdtTextTestUtils.editContext('B')..insert(0, 'b');
      final remote = CrdtTextTestUtils.save(b);
      a.applyChange(remote);
      a.insert(a.length, '!');
      final local = CrdtTextTestUtils.save(a);
      expect(
        local.operations.map((operation) => operation.id.actorId),
        everyElement('A'),
      );

      final receiver = CrdtText();
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
      final a = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
      final prepared = a.prepareChange()!;
      final b = CrdtTextTestUtils.editContext('B')..applyChange(prepared);
      b.insert(1, 'b');
      final reply = CrdtTextTestUtils.save(b);
      a.applyChange(reply);
      a.insert(2, 'c');
      a.acknowledgeChange(prepared);
      final later = CrdtTextTestUtils.save(a);
      b.applyChange(later);
      expect(b.text, 'abc');
      expect(a.text, b.text);
    });

    test('rejects another writer extending the local actor while dirty', () {
      final a = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
      final other = CrdtTextTestUtils.editContext('A')
        ..applyChange(a.prepareChange()!);
      other.insert(1, 'b');
      final before = a.prepareChange();
      expect(
        () => a.applyChange(CrdtTextTestUtils.save(other)),
        throwsA(isA<CrdtTextException>()),
      );
      expect(a.text, 'a');
      expect(a.prepareChange(), same(before));
      a.acknowledgeChange(before!);
      expect(a.hasPendingChanges, isFalse);
    });
  });

  group('JSON persistence', () {
    test('empty state round trips', () {
      final text = CrdtText();
      final restored = CrdtText.fromJson(jsonCopy(text.toJson()));
      expect(restored.toJson(), text.toJson());
    });

    test('restores tombstones and permits later insertion after them', () {
      final a = CrdtTextTestUtils.editContext('A')..insert(0, 'abc');
      final initial = CrdtTextTestUtils.save(a);
      final document = CrdtText()..applyChange(initial);
      final b = CrdtTextTestUtils.editContext('B')..applyChange(initial);
      a.delete(1, 2);
      document.applyChange(CrdtTextTestUtils.save(a));
      b.insert(2, 'X');
      final restored = CrdtText.fromJson(jsonCopy(document.toJson()));
      restored.applyChange(CrdtTextTestUtils.save(b));
      expect(restored.text, 'aXc');
    });

    test('snapshots contain document history without local editing state', () {
      final document = CrdtText();
      final context = CrdtTextTestUtils.editContext('A', document: document)
        ..insert(0, 'a😀');
      document.applyChange(CrdtTextTestUtils.save(context));
      context.insert(context.length, 'b');
      context.prepareChange();
      context.insert(context.length, 'c');

      final snapshot = jsonCopy(document.toJson());
      expect(snapshot.keys, ['operations']);
      final restored = CrdtText.fromJson(snapshot);
      expect(restored.text, 'a😀');
      expect(restored.toJson(), snapshot);
      final fresh = CrdtTextTestUtils.editContext('A', document: restored);
      expect(fresh.hasPendingChanges, isFalse);
      expect(fresh.prepareChange(), isNull);
    });

    for (final actor in ['A', 'B']) {
      test('restored history can be edited by actor $actor', () {
        final document = CrdtText();
        final original = CrdtTextTestUtils.editContext('A', document: document)
          ..insert(0, 'ab');
        document.applyChange(CrdtTextTestUtils.save(original));
        original.delete(1, 2);
        document.applyChange(CrdtTextTestUtils.save(original));
        final snapshot = jsonCopy(document.toJson());
        final restored = CrdtText.fromJson(snapshot);
        final context = CrdtTextTestUtils.editContext(
          actor,
          document: restored,
        );
        context.insert(1, '!');
        final change = context.prepareChange()!;
        expect(change.operations.single.id, textId(4, actor));
        expect(change.operations.single.dependencies, {'A': 3});
        restored.applyChange(change);
        expect(restored.text, 'a!');
        expect(document.toJson(), snapshot);
      });
    }

    test('snapshot export does not prepare local edits', () {
      final document = CrdtText();
      final context = CrdtTextTestUtils.editContext('A', document: document)
        ..insert(0, 'a');
      document.toJson();
      context.insert(1, 'b');
      expect(context.prepareChange()!.operations, hasLength(2));
    });

    test('snapshot export does not acknowledge a prepared batch', () {
      final document = CrdtText();
      final context = CrdtTextTestUtils.editContext('A', document: document)
        ..insert(0, 'a');
      final prepared = context.prepareChange()!;
      document.applyChange(prepared);
      document.toJson();
      expect(context.prepareChange(), same(prepared));
      expect(context.hasPendingChanges, isTrue);
    });

    test('change JSON round trips insertions and deletions', () {
      final text = CrdtTextTestUtils.editContext('A')..insert(0, 'x😀');
      text.delete(0, 1);
      final change = text.prepareChange()!;
      expect(change.toJson().keys, ['operations']);
      final restored = CrdtTextChange.fromJson(jsonCopy(change.toJson()));
      expect(restored, change);
      expect(restored.hashCode, change.hashCode);
      final replica = CrdtText()..applyChange(restored);
      expect(replica.text, '😀');
    });

    test('restored state detects a conflicting duplicate', () {
      final text = CrdtText()..applyChange(CrdtTextChange([insertion(1)]));
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
      final text = CrdtText()..applyChange(CrdtTextChange([insertion(1)]));
      final before = text.toJson();
      final json = text.toJson();
      ((json['operations'] as List).first as Map)['character'] = 'b';
      (json['operations'] as List).clear();
      expect(text.toJson(), before);
    });

    final corruptions =
        <(String, void Function(Map<String, Object?>), Matcher)>[
          (
            'empty operation actor',
            (json) {
              (((json['operations'] as List).first as Map)['id']
                      as Map)['actorId'] =
                  '';
            },
            throwsArgumentError,
          ),
          (
            'missing operations',
            (json) => json.remove('operations'),
            throwsA(isA<TypeError>()),
          ),
          (
            'duplicate operation',
            (json) {
              final operations = json['operations'] as List;
              operations.add(operations.first);
            },
            throwsFormatException,
          ),
          (
            'unknown operation kind',
            (json) {
              ((json['operations'] as List).first as Map)['kind'] = 'other';
            },
            throwsFormatException,
          ),
          (
            'invalid scalar',
            (json) {
              ((json['operations'] as List).first as Map)['character'] = 'ab';
            },
            throwsArgumentError,
          ),
          (
            'noninteger counter',
            (json) {
              (((json['operations'] as List).first as Map)['id']
                      as Map)['counter'] =
                  1.5;
            },
            throwsA(isA<TypeError>()),
          ),
          (
            'missing causal predecessor',
            (json) {
              (json['operations'] as List).removeAt(0);
            },
            throwsA(isA<CrdtTextException>()),
          ),
        ];
    for (final (name, corrupt, expectedError) in corruptions) {
      test('rejects snapshot with $name', () {
        final context = CrdtTextTestUtils.editContext('A')..insert(0, 'ab');
        final text = CrdtText()..applyChange(CrdtTextTestUtils.save(context));
        final json = jsonCopy(text.toJson());
        corrupt(json);
        expect(() => CrdtText.fromJson(json), expectedError);
      });
    }

    for (final json in [null, [], {}]) {
      test('rejects malformed change $json', () {
        expect(() => CrdtTextChange.fromJson(json), throwsA(isA<TypeError>()));
      });
    }

    test('rejects a decoded change without operations', () {
      expect(
        () => CrdtTextChange.fromJson({'operations': []}),
        throwsArgumentError,
      );
    });
  });
}
