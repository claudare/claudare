import 'dart:math';

import 'package:crdt/crdt.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  group('local editing', () {
    test('starts empty without pending changes', () {
      final text = CrdtText(actorId: 'A');
      expect(text.text, '');
      expect(text.length, 0);
      expect(text.prepareChange(), isNull);
    });

    test('inserts at the head, middle, and tail', () {
      final text = CrdtText(actorId: 'A');
      text.insert(0, 'elo');
      text.insert(0, 'H');
      text.insert(3, 'l');
      text.insert(5, '!');
      expect(text.text, 'Hello!');
    });

    test('replaces a range with a longer string', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'Hi');
      text.replace(1, 2, 'ello');
      expect(text.text, 'Hello');
    });

    test('supports complete deletion followed by insertion', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'hello');
      text.delete(0, 5);
      expect(text.text, '');
      text.insert(0, 'new');
      expect(text.text, 'new');
    });

    test('no-op edits do not allocate operations or notify', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'abc');
      save(text);
      var notifications = 0;
      text.addListener(() => notifications++);
      text.insert(1, '');
      text.delete(1, 1);
      text.replace(0, 3, 'abc');
      expect(text.prepareChange(), isNull);
      expect(notifications, 0);
    });

    test('uses UTF-16 offsets without normalizing Unicode', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'a😀e\u0301👩‍💻\r\n');
      expect(text.length, 'a😀e\u0301👩‍💻\r\n'.length);
      text.replace(1, 3, '🌍');
      expect(text.text, 'a🌍e\u0301👩‍💻\r\n');
    });

    for (final range in [(-1, 0), (0, 4), (2, 1), (1, 1), (0, 1)]) {
      test('rejects invalid or split-surrogate range $range atomically', () {
        final text = CrdtText(actorId: 'A')..insert(0, '😀x');
        final before = text.toJson();
        expect(
          () => text.replace(range.$1, range.$2, 'y'),
          throwsArgumentError,
        );
        expect(text.toJson(), before);
      });
    }

    for (final invalid in ['\ud800', '\udc00', '\ud800x']) {
      test('rejects malformed Unicode ${invalid.codeUnits}', () {
        final text = CrdtText(actorId: 'A');
        expect(() => text.insert(0, invalid), throwsArgumentError);
        expect(text.hasPendingChanges, isFalse);
      });
    }

    test('reports a replacement only after it is fully applied', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'abc');
      final observed = <String>[];
      text.addListener(() => observed.add(text.text));
      text.replace(0, 2, 'XY');
      expect(observed, ['XYc']);
    });

    test('traverses a long insertion chain without recursive calls', () {
      final content = List.filled(3000, 'a').join();
      final text = CrdtText(actorId: 'A')..insert(0, content);
      expect(text.text, content);
    });

    test('random edits agree with ordinary string replacement', () {
      final random = Random(817);
      const alphabet = ['a', 'b', '😀', 'é', '\u0301', '\n'];
      for (var trial = 0; trial < 15; trial++) {
        var expected = '';
        var text = CrdtText(actorId: 'writer');
        for (var step = 0; step < 100; step++) {
          final boundaries = [0];
          for (final rune in expected.runes) {
            boundaries.add(boundaries.last + String.fromCharCode(rune).length);
          }
          final first = random.nextInt(boundaries.length);
          final last = first + random.nextInt(boundaries.length - first);
          final replacement = List.generate(
            random.nextInt(4),
            (_) => alphabet[random.nextInt(alphabet.length)],
          ).join();
          text.replace(boundaries[first], boundaries[last], replacement);
          expected = expected.replaceRange(
            boundaries[first],
            boundaries[last],
            replacement,
          );
          expect(text.text, expected, reason: 'trial $trial, step $step');
          if (step % 25 == 0) text = CrdtText.fromJson(jsonCopy(text.toJson()));
        }
      }
    });
  });

  group('causal application', () {
    test('accepts a local event-log echo without acknowledging it', () {
      final text = CrdtText(actorId: 'A')..insert(0, 'hello');
      final change = text.prepareChange()!;
      final before = text.toJson();
      text.applyChange(CrdtTextChange.fromJson(jsonCopy(change.toJson())));
      expect(text.toJson(), before);
      expect(text.hasPendingChanges, isTrue);
    });

    test('replay does not create unsaved edits', () {
      final source = CrdtText(actorId: 'A')..insert(0, 'hello');
      final receiver = CrdtText(actorId: 'B')..applyChange(save(source));
      expect(receiver.text, 'hello');
      expect(receiver.hasPendingChanges, isFalse);
    });

    test('clock advances past received deletion IDs', () {
      final source = CrdtText(actorId: 'A')..insert(0, 'x');
      final receiver = CrdtText(actorId: 'B')..applyChange(save(source));
      source.delete(0, 1);
      receiver.applyChange(save(source));
      receiver.insert(0, 'y');
      expect(receiver.prepareChange()!.operations.single.id.counter, 3);
    });

    test('accepts an older counter from a concurrent actor', () {
      final first = CrdtText(actorId: 'A')..insert(0, 'abc');
      final second = CrdtText(actorId: 'B')..insert(0, 'x');
      first.applyChange(save(second));
      expect(first.text, 'xabc');
    });

    test('duplicate changes do not notify twice', () {
      final source = CrdtText(actorId: 'A')..insert(0, 'x');
      final change = save(source);
      final receiver = CrdtText(actorId: 'B');
      var notifications = 0;
      receiver.addListener(() => notifications++);
      receiver.applyChange(change);
      receiver.applyChange(change);
      expect(notifications, 1);
    });

    test('rejects a later causal batch until its predecessor arrives', () {
      final source = CrdtText(actorId: 'A')..insert(0, 'a');
      final first = save(source);
      source.insert(0, 'b');
      final second = save(source);
      final receiver = CrdtText(actorId: 'B');
      expect(
        () => receiver.applyChange(second),
        throwsA(isA<CrdtTextException>()),
      );
      expect(receiver.text, '');
      receiver.applyChange(first);
      receiver.applyChange(second);
      expect(receiver.text, 'ba');
    });

    test('rejects a whole batch if its last operation is invalid', () {
      final receiver = CrdtText(actorId: 'B');
      final before = receiver.toJson();
      var notifications = 0;
      receiver.addListener(() => notifications++);
      final change = CrdtTextChange([
        insertion(1),
        insertion(3, dependencies: {'A': 1}, after: textId(1)),
      ]);
      expect(
        () => receiver.applyChange(change),
        throwsA(isA<CrdtTextException>()),
      );
      expect(receiver.toJson(), before);
      expect(notifications, 0);
    });

    test('rejects conflicting reuse of an ID atomically', () {
      final receiver = CrdtText(actorId: 'B')
        ..applyChange(CrdtTextChange([insertion(1)]));
      final before = receiver.toJson();
      expect(
        () => receiver.applyChange(
          CrdtTextChange([insertion(1, character: 'y')]),
        ),
        throwsA(isA<CrdtTextException>()),
      );
      expect(receiver.toJson(), before);
    });

    test('rejects references absent from the author context', () {
      final receiver = CrdtText(actorId: 'B')
        ..applyChange(CrdtTextChange([insertion(1)]));
      final invalid = insertion(1, actor: 'C', after: textId(1));
      expect(
        () => receiver.applyChange(CrdtTextChange([invalid])),
        throwsA(isA<CrdtTextException>()),
      );
    });

    test('rejects a reference to a deletion operation', () {
      final source = CrdtText(actorId: 'A')..insert(0, 'a');
      source.delete(0, 1);
      final receiver = CrdtText(actorId: 'B')..applyChange(save(source));
      final invalid = CrdtTextDelete(
        id: textId(3, 'C'),
        dependencies: {'A': 2},
        target: textId(2),
      );
      expect(
        () => receiver.applyChange(CrdtTextChange([invalid])),
        throwsA(isA<CrdtTextException>()),
      );
    });

    test('rejects a context that omits transitive dependencies', () {
      final a = CrdtText(actorId: 'A')..insert(0, 'a');
      final b = CrdtText(actorId: 'B')..applyChange(save(a));
      b.insert(1, 'b');
      final c = CrdtText(actorId: 'C');
      c.applyChange(CrdtTextChange([insertion(1, character: 'a')]));
      c.applyChange(save(b));
      final invalid = insertion(3, actor: 'D', dependencies: {'B': 2});
      expect(
        () => c.applyChange(CrdtTextChange([invalid])),
        throwsA(isA<CrdtTextException>()),
      );
    });
  });
}
