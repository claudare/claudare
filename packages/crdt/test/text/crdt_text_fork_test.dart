import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

void main() {
  test('fork preserves operations and tombstones', () {
    final document = CrdtText();
    CrdtTextTestUtils.applyChangeToDocument(document, 'Hello');
    CrdtTextTestUtils.applyChangeToDocument(document, 'Helo', actorId: 'b');

    final fork = document.fork();

    expect(fork, isNot(same(document)));
    expect(fork.toJson(), document.toJson());
    expect(fork.text, 'Helo');
  });

  for (final editFork in [false, true]) {
    test('mutations and listeners are isolated when editFork=$editFork', () {
      final document = CrdtText();
      CrdtTextTestUtils.applyChangeToDocument(document, 'Original');
      var documentNotifications = 0;
      document.addListener(() => documentNotifications++);
      final fork = document.fork();
      var forkNotifications = 0;
      fork.addListener(() => forkNotifications++);
      final edited = editFork ? fork : document;
      final unchanged = editFork ? document : fork;
      final before = unchanged.toJson();

      CrdtTextTestUtils.applyChangeToDocument(edited, 'Edited');

      expect(edited.text, 'Edited');
      expect(unchanged.toJson(), before);
      expect(documentNotifications, editFork ? 0 : 1);
      expect(forkNotifications, editFork ? 1 : 0);
    });
  }

  test('concurrent edits on forks converge through change delivery', () {
    final left = CrdtText();
    CrdtTextTestUtils.applyChangeToDocument(left, 'Hello', actorId: 'seed');
    final right = left.fork();
    final leftChange = CrdtTextTestUtils.applyChangeToDocument(
      left,
      'Hello!',
      actorId: 'alice',
    )!;
    final rightChange = CrdtTextTestUtils.applyChangeToDocument(
      right,
      'Hi Hello',
      actorId: 'bob',
    )!;

    left.applyChange(rightChange);
    right.applyChange(leftChange);

    expect(left.text, 'Hi Hello!');
    expect(left.toJson(), right.toJson());
  });
}
