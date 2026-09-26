import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

import 'text_test_support.dart';

void main() {
  test('rejects an empty actor ID', () {
    expect(() => CrdtTextTestUtils.editContext(''), throwsArgumentError);
  });

  test('copies existing history without creating pending edits', () {
    final document = CrdtText()..applyChange(CrdtTextChange([insertion(1)]));
    final context = CrdtTextTestUtils.editContext('B', document: document);
    expect(context.actorId, 'B');
    expect(context.text, 'x');
    expect(context.length, 1);
    expect(context.hasPendingChanges, isFalse);
    expect(context.prepareChange(), isNull);
  });

  test('local edits do not mutate or notify the source document', () {
    final document = CrdtText()..applyChange(CrdtTextChange([insertion(1)]));
    final before = document.toJson();
    var notifications = 0;
    document.addListener(() => notifications++);
    final context = CrdtTextTestUtils.editContext('B', document: document);
    context.replace(0, 1, 'draft');
    expect(context.text, 'draft');
    expect(document.toJson(), before);
    expect(notifications, 0);
  });

  test('source changes do not implicitly update or notify the draft', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('B', document: document);
    var notifications = 0;
    context.addListener(() => notifications++);
    document.applyChange(CrdtTextChange([insertion(1)]));
    expect(context.text, '');
    expect(context.hasPendingChanges, isFalse);
    expect(notifications, 0);
  });

  test('incoming draft changes do not mutate the source document', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('B', document: document);
    context.applyChange(CrdtTextChange([insertion(1)]));
    expect(context.text, 'x');
    expect(document.text, '');
    expect(document.toJson()['operations'], isEmpty);
  });

  test('acknowledgment does not apply a change to the source document', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('A', document: document)
      ..insert(0, 'draft');
    context.acknowledgeChange(context.prepareChange()!);
    expect(document.text, '');
    expect(document.toJson()['operations'], isEmpty);
    expect(context.text, 'draft');
  });

  test('contexts from one document own independent drafts and batches', () {
    final document = CrdtText();
    final a = CrdtTextTestUtils.editContext('A', document: document);
    final b = CrdtTextTestUtils.editContext('B', document: document);
    a.insert(0, 'a');
    b.insert(0, 'b');
    expect(a.text, 'a');
    expect(b.text, 'b');
    expect(a.prepareChange()!.actorId, 'A');
    expect(b.prepareChange()!.actorId, 'B');
  });

  test('copied tombstones retain anchors for incoming edits', () {
    final author = CrdtTextTestUtils.editContext('A')..insert(0, 'abc');
    final initial = CrdtTextTestUtils.save(author);
    final document = CrdtText()..applyChange(initial);
    final remote = CrdtTextTestUtils.editContext('B', document: document);
    author.delete(1, 2);
    document.applyChange(CrdtTextTestUtils.save(author));
    final context = CrdtTextTestUtils.editContext('C', document: document);
    remote.insert(2, 'X');
    context.applyChange(CrdtTextTestUtils.save(remote));
    expect(context.text, 'aXc');
    expect(context.hasPendingChanges, isFalse);
  });

  test('accepted local edits are pending before listeners run', () {
    final context = CrdtTextTestUtils.editContext('A');
    CrdtTextChange? observed;
    context.addListener(() => observed = context.prepareChange());
    context.insert(0, 'a');
    final replay = CrdtText()..applyChange(observed!);
    expect(replay.text, 'a');
  });

  test('accepts another writer extending the actor after acknowledgment', () {
    final context = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
    final document = CrdtText()..applyChange(CrdtTextTestUtils.save(context));
    final other = CrdtTextTestUtils.editContext('A', document: document)
      ..insert(1, 'b');
    context.applyChange(CrdtTextTestUtils.save(other));
    expect(context.text, 'ab');
    expect(context.hasPendingChanges, isFalse);
    context.insert(2, 'c');
    expect(context.prepareChange()!.operations.single.id, textId(3));
  });

  test('invalid incoming batches preserve the draft and pending edits', () {
    final context = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
    final pending = context.prepareChange()!;
    var notifications = 0;
    context.addListener(() => notifications++);
    final invalid = CrdtTextChange([
      insertion(1, actor: 'B'),
      insertion(3, actor: 'B', dependencies: {'B': 1}),
    ]);
    expect(
      () => context.applyChange(invalid),
      throwsA(isA<CrdtTextException>()),
    );
    expect(context.text, 'a');
    expect(context.prepareChange(), same(pending));
    expect(notifications, 0);
    context.acknowledgeChange(pending);
    expect(context.hasPendingChanges, isFalse);
  });
}
