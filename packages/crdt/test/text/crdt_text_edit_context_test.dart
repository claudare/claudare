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

  test('source changes update and notify the draft', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('B', document: document);
    var notifications = 0;
    context.addListener(() => notifications++);
    document.applyChange(CrdtTextChange([insertion(1)]));
    expect(context.text, 'x');
    expect(context.hasPendingChanges, isFalse);
    expect(notifications, 1);
  });

  test('disposing twice detaches the draft from source changes', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('B', document: document);
    context.dispose();
    context.dispose();
    document.applyChange(CrdtTextChange([insertion(1)]));
    expect(context.text, '');
    expect(document.text, 'x');
  });

  test('source application acknowledges the prepared batch', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('A', document: document)
      ..insert(0, 'draft');
    document.applyChange(context.prepareChange()!);
    expect(document.text, 'draft');
    expect(context.hasPendingChanges, isFalse);
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
    final remote = CrdtTextTestUtils.editContext(
      'B',
      document: document.fork(),
    );
    author.delete(1, 2);
    document.applyChange(CrdtTextTestUtils.save(author));
    final context = CrdtTextTestUtils.editContext('C', document: document);
    remote.insert(2, 'X');
    document.applyChange(CrdtTextTestUtils.save(remote));
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

  test(
    'a listener can persist a local edit without recursive notification',
    () {
      final context = CrdtTextTestUtils.editContext('A');
      var notifications = 0;
      context.addListener(() {
        notifications++;
        context.document.applyChange(context.prepareChange()!);
      });
      context.insert(0, 'a');
      expect(notifications, 1);
      expect(context.document.text, 'a');
      expect(context.hasPendingChanges, isFalse);
    },
  );

  test('accepts another writer extending the actor after acknowledgment', () {
    final context = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
    final document = CrdtText()..applyChange(CrdtTextTestUtils.save(context));
    final other = CrdtTextTestUtils.editContext('A', document: document)
      ..insert(1, 'b');
    context.document.applyChange(CrdtTextTestUtils.save(other));
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
      () => context.document.applyChange(invalid),
      throwsA(isA<CrdtTextException>()),
    );
    expect(context.text, 'a');
    expect(context.prepareChange(), same(pending));
    expect(notifications, 0);
    context.document.applyChange(pending);
    expect(context.hasPendingChanges, isFalse);
  });

  test('acknowledges a prepared batch delivered in separate pieces', () {
    final context = CrdtTextTestUtils.editContext('A')..insert(0, 'ab');
    final prepared = context.prepareChange()!;
    context.insert(2, 'c');
    context.document.applyChange(CrdtTextChange([prepared.operations.first]));
    expect(context.prepareChange(), same(prepared));
    context.document.applyChange(CrdtTextChange([prepared.operations.last]));
    expect(context.prepareChange()!.operations.single.id, textId(3));
    expect(context.document.text, 'ab');
    expect(context.text, 'abc');
  });

  test('acknowledges a prepared batch contained in a larger batch', () {
    final context = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
    final prepared = context.prepareChange()!;
    final remote = CrdtTextTestUtils.editContext('A');
    remote.document.applyChange(prepared);
    remote.insert(1, 'b');
    final later = remote.prepareChange()!;
    context.document.applyChange(
      CrdtTextChange([...prepared.operations, ...later.operations]),
    );
    expect(context.text, 'ab');
    expect(context.prepareChange(), isNull);
  });

  test('matching operation IDs with different contents do not acknowledge', () {
    final context = CrdtTextTestUtils.editContext('A')..insert(0, 'a');
    final prepared = context.prepareChange()!;
    expect(
      () => context.document.applyChange(
        CrdtTextChange([insertion(1, character: 'b')]),
      ),
      throwsA(isA<CrdtTextException>()),
    );
    expect(context.text, 'a');
    expect(context.prepareChange(), same(prepared));
  });

  test('source retry reconciles a context skipped by a failing listener', () {
    final document = CrdtText();
    var fail = true;
    document.addListener(() {
      if (fail) throw StateError('Listener failed');
    });
    final context = CrdtTextTestUtils.editContext('B', document: document);
    final change = CrdtTextTestUtils.singleChange('remote');
    expect(() => document.applyChange(change), throwsStateError);
    expect(context.text, '');
    fail = false;
    document.applyChange(change);
    expect(context.text, 'remote');
    expect(context.hasPendingChanges, isFalse);
  });

  test('source retry notifies a draft listener after its earlier failure', () {
    final context = CrdtTextTestUtils.editContext('B');
    var fail = true;
    final observed = <String>[];
    context.addListener(() {
      if (fail) throw StateError('Editor failed');
      observed.add(context.text);
    });
    final change = CrdtTextTestUtils.singleChange('remote');
    expect(() => context.document.applyChange(change), throwsStateError);
    fail = false;
    context.document.applyChange(change);
    context.document.applyChange(change);
    expect(observed, ['remote']);
  });
}
