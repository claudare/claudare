import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  for (final (before, after) in [
    ('', 'hello'),
    ('abc', ''),
    ('ab', 'aXb'),
    ('abc', 'ac'),
    ('abc', 'aXYc'),
    ('abc', 'xyz'),
    ('abcde', 'aXcYe'),
    ('😀a🌍', '😀b🌍'),
    ('a😀b', 'a😁b'),
    ('e\u0301', 'e\u0301!'),
  ]) {
    test('updates and replays $before to $after', () {
      final (document, context) = _editing(before);
      updateText(context, after);
      expect(context.text, after);
      expect(document.text, before);
      document.applyChange(context.prepareChange()!);
      expect(document.text, after);
    });
  }

  for (final value in ['', 'aaa', '😀']) {
    test('identical text $value produces no edits or notifications', () {
      final (_, context) = _editing(value);
      var notifications = 0;
      context.addListener(() => notifications++);
      updateText(context, value);
      expect(context.prepareChange(), isNull);
      expect(notifications, 0);
    });
  }

  for (final (before, after, deletedCounters, insertedText, anchorCounter) in [
    ('abc', 'aXc', [2], 'X', 1),
    ('aaa', 'aa', [3], '', 0),
    ('aa', 'aaa', <int>[], 'a', 2),
    ('😀a🌍', '😀b🌍', [2], 'b', 1),
    ('a😀b', 'a😁b', [2], '😁', 1),
  ]) {
    test('preserves unchanged character IDs for $before to $after', () {
      final (_, context) = _editing(before);
      updateText(context, after);
      final change = context.prepareChange()!;
      expect(
        change.operations.whereType<CrdtTextDelete>().map((op) => op.target),
        deletedCounters.map((counter) => textId(counter, 'source')),
      );
      final inserts = change.operations.whereType<CrdtTextInsert>().toList();
      expect(inserts.map((op) => op.character).join(), insertedText);
      if (inserts.isNotEmpty) {
        expect(inserts.first.after, textId(anchorCounter, 'source'));
      }
    });
  }

  test('notifies once with the complete updated text', () {
    final (_, context) = _editing('abc');
    final observed = <String>[];
    context.addListener(() => observed.add(context.text));
    updateText(context, 'aXYc');
    expect(observed, ['aXYc']);
  });

  for (final invalid in ['\ud800', 'a\udc00b', '😀\ud800🌍']) {
    test('rejects malformed Unicode ${invalid.codeUnits} without mutation', () {
      final (_, context) = _editing('😀a🌍');
      context.insert(context.length, '!');
      final prepared = context.prepareChange()!;
      var notifications = 0;
      context.addListener(() => notifications++);
      expect(() => updateText(context, invalid), throwsArgumentError);
      expect(context.text, '😀a🌍!');
      expect(context.prepareChange(), same(prepared));
      expect(notifications, 0);
      context.acknowledgeChange(prepared);
      expect(context.hasPendingChanges, isFalse);
    });
  }

  test('updates after preparation stay pending for the next batch', () {
    final (document, context) = _editing('');
    updateText(context, 'hello');
    final first = context.prepareChange()!;
    updateText(context, 'hello!');
    expect(context.prepareChange(), same(first));
    document.applyChange(first);
    context.acknowledgeChange(first);
    final later = context.prepareChange()!;
    expect(later.operations, hasLength(1));
    document.applyChange(later);
    expect(document.text, 'hello!');
  });
}

(CrdtText, CrdtTextEditContext) _editing(String initial) {
  final document = CrdtText();
  if (initial.isNotEmpty) {
    final source = editContext('source')..insert(0, initial);
    document.applyChange(save(source));
  }
  return (document, editContext('writer', document: document));
}
