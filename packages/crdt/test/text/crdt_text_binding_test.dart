import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  group('editor binding', () {
    test('initializes text and caret from the document', () {
      final f = _Fixture('hello😀');
      addTearDown(f.binding.dispose);
      expect(f.controller.value.text, 'hello😀');
      expect(f.controller.value.selectionExtent, 7);
      expect(f.local.hasPendingChanges, isFalse);
    });

    test(
      'turns a local replacement into a replayable change without feedback',
      () {
        final f = _Fixture('hello');
        addTearDown(f.binding.dispose);
        f.controller.edit('help!', 5);
        expect(f.local.text, 'help!');
        expect(f.controller.assignments, 2);
        f.remote.applyChange(save(f.local));
        expect(f.remote.text, 'help!');
      },
    );

    test('remote editor refresh does not create outgoing edits', () {
      final f = _Fixture('ab');
      addTearDown(f.binding.dispose);
      f.remote.insert(1, 'R');
      f.local.applyChange(save(f.remote));
      expect(f.controller.value.text, 'aRb');
      expect(f.local.prepareChange(), isNull);
      expect(f.controller.assignments, 2);
    });

    test('selection and composition changes alone do not generate events', () {
      final f = _Fixture('abc');
      addTearDown(f.binding.dispose);
      f.controller.edit('abc', 1);
      f.controller.edit('abc', 2, composingStart: 1, composingEnd: 2);
      f.controller.edit('abc', 2);
      expect(f.local.prepareChange(), isNull);
    });

    test('remote insertion at the caret moves it after the insertion', () {
      final f = _Fixture('ab');
      addTearDown(f.binding.dispose);
      f.controller.edit('ab', 1);
      f.remote.insert(1, 'R');
      f.local.applyChange(save(f.remote));
      expect(f.controller.value.selectionBase, 2);
      expect(f.controller.value.selectionExtent, 2);
    });

    test(
      'remote insertion after the caret leaves it at its character anchor',
      () {
        final f = _Fixture('abc');
        addTearDown(f.binding.dispose);
        f.controller.edit('abc', 1);
        f.remote.insert(3, 'R');
        f.local.applyChange(save(f.remote));
        expect(f.controller.value.selectionExtent, 1);
      },
    );

    test('deletion containing a caret collapses it at the deleted region', () {
      final f = _Fixture('abcd');
      addTearDown(f.binding.dispose);
      f.controller.edit('abcd', 2);
      f.remote.delete(1, 3);
      f.local.applyChange(save(f.remote));
      expect(f.controller.value.text, 'ad');
      expect(f.controller.value.selectionExtent, 1);
    });

    for (final reversed in [false, true]) {
      test(
        'preserves ${reversed ? 'reversed' : 'forward'} selection boundaries',
        () {
          final f = _Fixture('abcd');
          addTearDown(f.binding.dispose);
          f.controller.value = CrdtTextEditingValue(
            text: 'abcd',
            selectionBase: reversed ? 3 : 1,
            selectionExtent: reversed ? 1 : 3,
            affinity: CrdtTextAffinity.upstream,
            isDirectional: true,
          );
          f.remote.insert(3, 'Y');
          f.remote.insert(1, 'X');
          f.local.applyChange(save(f.remote));
          expect(f.controller.value.text, 'aXbcYd');
          expect(f.controller.value.selectionBase, reversed ? 4 : 2);
          expect(f.controller.value.selectionExtent, reversed ? 2 : 4);
          expect(f.controller.value.affinity, CrdtTextAffinity.upstream);
          expect(f.controller.value.isDirectional, isTrue);
        },
      );
    }

    test('preserves an absent selection when the document changes', () {
      final f = _Fixture('abc');
      addTearDown(f.binding.dispose);
      f.controller.value = CrdtTextEditingValue(text: 'abc');
      f.remote.delete(0, 3);
      f.local.applyChange(save(f.remote));
      expect(f.controller.value.selectionBase, -1);
      expect(f.controller.value.selectionExtent, -1);
    });

    test(
      'preserves a selection inside a surrogate pair during unrelated edits',
      () {
        final f = _Fixture('😀b');
        addTearDown(f.binding.dispose);
        f.controller.edit('😀b', 1);
        f.remote.insert(0, 'a');
        f.local.applyChange(save(f.remote));
        expect(f.controller.value.selectionExtent, 2);
        f.remote.delete(1, 3);
        f.local.applyChange(save(f.remote));
        expect(f.controller.value.selectionExtent, 1);
      },
    );

    test('replaces a whole emoji when two emoji share a leading surrogate', () {
      final f = _Fixture('😀');
      addTearDown(f.binding.dispose);
      f.controller.edit('😁', 2);
      final change = save(f.local);
      f.remote.applyChange(change);
      expect(f.remote.text, '😁');
      expect(
        change.operations.whereType<CrdtTextInsert>().single.character,
        '😁',
      );
    });

    test('preserves combining characters during a local edit', () {
      final f = _Fixture('e\u0301');
      addTearDown(f.binding.dispose);
      f.controller.edit('e\u0301!', 3);
      f.remote.applyChange(save(f.local));
      expect(f.remote.text, 'e\u0301!');
    });

    for (final (name, oldCaret, newCaret, expectedIndex) in [
      ('backspace', 2, 1, 1),
      ('forward delete', 1, 1, 1),
      ('delete at the start', 0, 0, 0),
      ('delete at the end', 3, 2, 2),
    ]) {
      test('uses the caret to disambiguate repeated text for $name', () {
        final f = _Fixture('aaa');
        addTearDown(f.binding.dispose);
        f.controller.edit('aaa', oldCaret);
        f.controller.edit('aa', newCaret);
        final deleted = f.local
            .prepareChange()!
            .operations
            .whereType<CrdtTextDelete>()
            .single;
        expect(deleted.target, textId(expectedIndex + 1, 'S'));
      });
    }

    test('uses the selected repeated character as the deletion target', () {
      final f = _Fixture('aaa');
      addTearDown(f.binding.dispose);
      f.controller.edit('aaa', 2, base: 1);
      f.controller.edit('aa', 1);
      final deleted = f.local
          .prepareChange()!
          .operations
          .whereType<CrdtTextDelete>()
          .single;
      expect(deleted.target, textId(2, 'S'));
    });

    test('inserts a repeated character at the caret', () {
      final f = _Fixture('aaa');
      addTearDown(f.binding.dispose);
      f.controller.edit('aaa', 1);
      f.controller.edit('aaaa', 2);
      final inserted = f.local
          .prepareChange()!
          .operations
          .whereType<CrdtTextInsert>()
          .single;
      expect(inserted.after, textId(1, 'S'));
    });

    test('supports edits from another bound controller', () {
      final f = _Fixture('ab');
      final otherController = FakeTextController();
      final other = CrdtTextBinding(text: f.local, controller: otherController);
      addTearDown(f.binding.dispose);
      addTearDown(other.dispose);
      otherController.edit('aXb', 2);
      expect(f.controller.value.text, 'aXb');
      f.controller.edit('aXYb', 3);
      expect(otherController.value.text, 'aXYb');
    });

    test('dispose detaches both directions and can be called twice', () {
      final f = _Fixture('ab');
      f.binding.dispose();
      f.binding.dispose();
      expect(f.controller.listeners, isEmpty);
      f.local.insert(0, 'x');
      expect(f.controller.value.text, 'ab');
      f.controller.edit('other', 5);
      expect(f.local.text, 'xab');
    });
  });

  group('composition', () {
    test('defers remote refresh until a composition-only completion', () {
      final f = _Fixture('ab');
      addTearDown(f.binding.dispose);
      f.controller.edit('ab', 1, composingStart: 0, composingEnd: 1);
      final assignments = f.controller.assignments;
      f.remote.insert(0, 'R');
      f.local.applyChange(save(f.remote));
      expect(f.local.text, 'Rab');
      expect(f.controller.value.text, 'ab');
      expect(f.controller.assignments, assignments);
      f.controller.edit('ab', 1);
      expect(f.controller.value.text, 'Rab');
      expect(f.controller.value.selectionExtent, 2);
      expect(f.local.hasPendingChanges, isFalse);
    });

    test('keeps local IME replacements and undisplayed remote insertions', () {
      final f = _Fixture('ab');
      addTearDown(f.binding.dispose);
      f.controller.edit('aにb', 2, composingStart: 1, composingEnd: 2);
      f.remote.insert(1, 'X');
      f.local.applyChange(save(f.remote));
      expect(f.local.text, 'aXにb');
      expect(f.controller.value.text, 'aにb');
      f.controller.edit('a日本b', 3, composingStart: 1, composingEnd: 3);
      expect(f.local.text, 'a日本Xb');
      expect(f.controller.value.text, 'a日本b');
      f.controller.edit('a日本b', 3);
      expect(f.controller.value.text, 'a日本Xb');
      expect(f.controller.value.selectionExtent, 4);
      f.remote.applyChange(save(f.local));
      expect(f.remote.text, f.local.text);
    });

    test('keeps an undisplayed insertion inside a local replacement range', () {
      final f = _Fixture('abcd');
      addTearDown(f.binding.dispose);
      f.controller.edit('abcd', 3, base: 1, composingStart: 1, composingEnd: 3);
      f.remote.insert(2, 'R');
      f.local.applyChange(save(f.remote));
      f.controller.edit('aXd', 2, composingStart: 1, composingEnd: 2);
      expect(f.local.text, 'aXRd');
      f.controller.edit('aXd', 2);
      expect(f.controller.value.text, 'aXRd');
      f.remote.applyChange(save(f.local));
      expect(f.remote.text, f.local.text);
    });

    test(
      'continues composition after remote deletion of its visible anchors',
      () {
        final f = _Fixture('ab');
        addTearDown(f.binding.dispose);
        f.controller.edit('aにb', 2, composingStart: 1, composingEnd: 2);
        f.remote.delete(0, 2);
        f.local.applyChange(save(f.remote));
        expect(f.controller.value.text, 'aにb');
        f.controller.edit('a日本b', 3, composingStart: 1, composingEnd: 3);
        f.controller.edit('a日本b', 3);
        expect(f.controller.value.text, '日本');
        expect(f.controller.value.selectionExtent, 2);
        f.remote.applyChange(save(f.local));
        expect(f.remote.text, '日本');
      },
    );

    test('cancelling composition preserves a remote insertion', () {
      final f = _Fixture('ab');
      addTearDown(f.binding.dispose);
      f.controller.edit('aにb', 2, composingStart: 1, composingEnd: 2);
      f.remote.insert(1, 'R');
      f.local.applyChange(save(f.remote));
      f.controller.edit('ab', 1);
      expect(f.controller.value.text, 'aRb');
      f.remote.applyChange(save(f.local));
      expect(f.remote.text, 'aRb');
    });

    test(
      'can save composing edits before receiving a reply that deletes them',
      () {
        final f = _Fixture('ab');
        addTearDown(f.binding.dispose);
        f.controller.edit('aにb', 2, composingStart: 1, composingEnd: 2);
        final batch = f.local.prepareChange()!;
        f.remote.applyChange(batch);
        f.remote.delete(1, 2);
        f.local.applyChange(save(f.remote));
        f.local.acknowledgeChange(batch);
        f.controller.edit('a日本b', 3, composingStart: 1, composingEnd: 3);
        f.controller.edit('a日本b', 3);
        f.remote.applyChange(save(f.local));
        expect(f.remote.text, 'a日本b');
        expect(f.controller.value.text, f.remote.text);
      },
    );

    test('handles an empty composition and remote initial text', () {
      final f = _Fixture('');
      addTearDown(f.binding.dispose);
      f.controller.edit('😀', 2, composingStart: 0, composingEnd: 2);
      f.remote.insert(0, 'R');
      f.local.applyChange(save(f.remote));
      f.controller.edit('😀', 2);
      expect(f.controller.value.text, 'R😀');
      expect(f.controller.value.selectionExtent, 3);
    });
  });
}

final class _Fixture {
  final CrdtText local = CrdtText(actorId: 'A');
  final CrdtText remote = CrdtText(actorId: 'B');
  final FakeTextController controller = FakeTextController();
  late final CrdtTextBinding binding;

  _Fixture(String content) {
    if (content.isNotEmpty) {
      final source = CrdtText(actorId: 'S')..insert(0, content);
      final initial = save(source);
      local.applyChange(initial);
      remote.applyChange(initial);
    }
    binding = CrdtTextBinding(text: local, controller: controller);
  }
}
