import 'dart:math';

import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  test('merges the transcript Helo example', () {
    final a = CrdtTextTestUtils.editContext('A')..insert(0, 'Helo');
    final b = CrdtTextTestUtils.editContext('B')
      ..applyChange(CrdtTextTestUtils.save(a));
    a.insert(3, 'l');
    b.insert(4, '!');
    final left = CrdtTextTestUtils.save(a);
    final right = CrdtTextTestUtils.save(b);
    a.applyChange(right);
    b.applyChange(left);
    expect(a.text, 'Hello!');
    expect(b.text, 'Hello!');
  });

  test('keeps concurrent forward insertion runs together', () {
    final source = CrdtTextTestUtils.editContext('S')..insert(0, 'ab');
    final initial = CrdtTextTestUtils.save(source);
    final a = CrdtTextTestUtils.editContext('A')..applyChange(initial);
    final b = CrdtTextTestUtils.editContext('B')..applyChange(initial);
    a.insert(2, 'de');
    b.insert(2, 'fg');
    final left = CrdtTextTestUtils.save(a);
    final right = CrdtTextTestUtils.save(b);
    a.applyChange(right);
    b.applyChange(left);
    expect(a.text, 'abfgde');
    expect(b.text, a.text);
  });

  test('merges overlapping deletions by insertion identity', () {
    final source = CrdtTextTestUtils.editContext('S')..insert(0, 'abcd');
    final initial = CrdtTextTestUtils.save(source);
    final a = CrdtTextTestUtils.editContext('A')..applyChange(initial);
    final b = CrdtTextTestUtils.editContext('B')..applyChange(initial);
    a.delete(1, 3);
    b.delete(2, 4);
    final left = CrdtTextTestUtils.save(a);
    final right = CrdtTextTestUtils.save(b);
    a.applyChange(right);
    b.applyChange(left);
    a.applyChange(right);
    expect(a.text, 'a');
    expect(b.text, 'a');
  });

  test(
    'exhaustive causal permutations preserve text and operation records',
    () {
      final source = CrdtTextTestUtils.editContext('S')..insert(0, 'x');
      final initial = CrdtTextTestUtils.save(source);
      final a = CrdtTextTestUtils.editContext('A')..applyChange(initial);
      final b = CrdtTextTestUtils.editContext('B')..applyChange(initial);
      final c = CrdtTextTestUtils.editContext('C')..applyChange(initial);
      a.insert(1, 'a');
      final firstA = CrdtTextTestUtils.save(a);
      a.insert(2, 'A');
      final secondA = CrdtTextTestUtils.save(a);
      b.insert(1, 'b');
      final firstB = CrdtTextTestUtils.save(b);
      b.insert(2, 'B');
      final secondB = CrdtTextTestUtils.save(b);
      c.delete(0, 1);
      final deletion = CrdtTextTestUtils.save(c);
      final changes = [firstA, secondA, firstB, secondB, deletion];
      Object? expectedOperations;
      var schedules = 0;
      for (final ordering in _permutations(changes)) {
        final known = initial.operations.map((op) => op.id).toSet();
        if (!ordering.every((change) {
          if (!_ready(change, known)) return false;
          known.addAll(change.operations.map((op) => op.id));
          return true;
        })) {
          continue;
        }
        schedules++;
        final replica = CrdtText()..applyChange(initial);
        for (final change in ordering) {
          replica.applyChange(change);
          replica.applyChange(
            CrdtTextChange.fromJson(jsonCopy(change.toJson())),
          );
        }
        expect(replica.text, 'bBaA');
        expectedOperations ??= replica.toJson()['operations'];
        expect(replica.toJson()['operations'], expectedOperations);
      }
      expect(schedules, 30);
    },
  );

  for (var seed = 0; seed < 16; seed++) {
    test(
      'seed $seed converges after partitions, duplicate delivery, and reload',
      () {
        final random = Random(seed);
        final documents = List.generate(3, (_) => CrdtText());
        final replicas = List.generate(
          3,
          (index) => CrdtTextTestUtils.editContext(
            'actor$index',
            document: documents[index],
          ),
        );
        final received = List.generate(3, (_) => <CrdtTextId>{});
        final history = <CrdtTextChange>[];
        const alphabet = ['a', 'b', 'c', '😀', '\u0301', '\n'];

        for (var step = 0; step < 90; step++) {
          final index = random.nextInt(replicas.length);
          final replica = replicas[index];
          if (random.nextInt(3) != 0) {
            final boundaries = [0];
            for (final rune in replica.text.runes) {
              boundaries.add(
                boundaries.last + String.fromCharCode(rune).length,
              );
            }
            final start = random.nextInt(boundaries.length);
            final end = start + random.nextInt(boundaries.length - start);
            final replacement = List.generate(
              random.nextInt(4),
              (_) => alphabet[random.nextInt(alphabet.length)],
            ).join();
            replica.replace(boundaries[start], boundaries[end], replacement);
            if (replica.hasPendingChanges) {
              final change = CrdtTextTestUtils.save(replica);
              documents[index].applyChange(change);
              history.add(change);
              received[index].addAll(change.operations.map((op) => op.id));
            }
          } else {
            final ready = history
                .where((change) => _ready(change, received[index]))
                .toList();
            if (ready.isNotEmpty) {
              final change = ready[random.nextInt(ready.length)];
              replica.applyChange(change);
              documents[index].applyChange(change);
              received[index].addAll(change.operations.map((op) => op.id));
            }
          }
          if (step % 19 == 0) {
            documents[index] = CrdtText.fromJson(
              jsonCopy(documents[index].toJson()),
            );
            replicas[index] = CrdtTextTestUtils.editContext(
              'actor$index',
              document: documents[index],
            );
          }
        }

        final allIds = history
            .expand((change) => change.operations)
            .map((op) => op.id)
            .toSet();
        for (var index = 0; index < replicas.length; index++) {
          while (received[index].length < allIds.length) {
            final ready =
                history
                    .where(
                      (change) =>
                          change.operations.any(
                            (op) => !received[index].contains(op.id),
                          ) &&
                          _ready(change, received[index]),
                    )
                    .toList()
                  ..shuffle(random);
            expect(
              ready,
              isNotEmpty,
              reason: 'The valid event history must make progress.',
            );
            for (final change in ready) {
              replicas[index].applyChange(
                CrdtTextChange.fromJson(jsonCopy(change.toJson())),
              );
              documents[index].applyChange(change);
              received[index].addAll(change.operations.map((op) => op.id));
            }
          }
        }

        final operations = history
            .expand((change) => change.operations)
            .toList();
        final deleted = operations
            .whereType<CrdtTextDelete>()
            .map((op) => op.target)
            .toSet();
        final expectedCharacters =
            operations
                .whereType<CrdtTextInsert>()
                .where((op) => !deleted.contains(op.id))
                .map((op) => op.character)
                .toList()
              ..sort();
        for (var index = 0; index < replicas.length; index++) {
          final replica = replicas[index];
          expect(replica.text, replicas.first.text);
          expect(documents[index].text, replica.text);
          expect(documents[index].toJson(), documents.first.toJson());
          final actualCharacters =
              replica.text.runes.map(String.fromCharCode).toList()..sort();
          expect(actualCharacters, expectedCharacters);
        }
      },
    );
  }
}

bool _ready(CrdtTextChange change, Set<CrdtTextId> known) {
  final available = Set<CrdtTextId>.of(known);
  for (final operation in change.operations) {
    if (!operation.dependencies.entries.every(
      (entry) => available.contains(
        CrdtTextId(actorId: entry.key, counter: entry.value),
      ),
    )) {
      return false;
    }
    available.add(operation.id);
  }
  return true;
}

Iterable<List<T>> _permutations<T>(List<T> items) sync* {
  if (items.isEmpty) {
    yield [];
    return;
  }
  for (var index = 0; index < items.length; index++) {
    final remainder = List<T>.of(items)..removeAt(index);
    for (final suffix in _permutations(remainder)) {
      yield [items[index], ...suffix];
    }
  }
}
