import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

void main() {
  test('successive full-text updates mutate the document and replay', () {
    final document = CrdtText();
    final replayed = CrdtText();
    for (final value in ['Hello', 'Hello, CRDT!', '']) {
      final change = CrdtTextTestUtils.applyChangeToDocument(document, value)!;
      replayed.applyChange(change);
      expect(document.text, value);
      expect(document.toJson(), replayed.toJson());
    }
  });

  test('an unchanged full-text update produces no change or notification', () {
    final document = CrdtText();
    CrdtTextTestUtils.applyChangeToDocument(document, 'Hello');
    final before = document.toJson();
    var notifications = 0;
    document.addListener(() => notifications++);

    expect(CrdtTextTestUtils.applyChangeToDocument(document, 'Hello'), isNull);
    expect(document.toJson(), before);
    expect(notifications, 0);
  });

  test('singleChange creates a fixture authored by the requested actor', () {
    final change = CrdtTextTestUtils.singleChange('Hello', actorId: 'alice');
    final document = CrdtText()..applyChange(change);
    expect(document.text, 'Hello');
    expect(change.actorId, 'alice');
  });

  test('singleChange rejects empty text', () {
    expect(() => CrdtTextTestUtils.singleChange(''), throwsArgumentError);
  });

  test('save acknowledges only the prepared batch', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('alice', document: document);
    context.insert(0, 'Hello');
    final prepared = context.prepareChange()!;
    context.insert(context.length, '!');

    expect(CrdtTextTestUtils.save(context), same(prepared));
    expect(document.text, 'Hello');
    expect(context.text, 'Hello!');
    expect(context.hasPendingChanges, isTrue);
    CrdtTextTestUtils.save(context);
    expect(document.text, 'Hello!');
    expect(context.prepareChange(), isNull);
  });

  test(
    'a failed document notification leaves the prepared batch retryable',
    () {
      final document = CrdtText();
      void fail() => throw StateError('Delivery interrupted');
      document.addListener(fail);
      final context = CrdtTextTestUtils.editContext('alice', document: document)
        ..insert(0, 'Hello');
      final prepared = context.prepareChange()!;

      expect(() => CrdtTextTestUtils.save(context), throwsStateError);
      expect(context.prepareChange(), same(prepared));
      expect(document.text, 'Hello');
    },
  );

  test('save rejects a context without pending edits', () {
    final context = CrdtTextTestUtils.editContext('alice');
    expect(() => CrdtTextTestUtils.save(context), throwsStateError);
  });

  test('duplicate delivery preserves local edits and their prepared batch', () {
    final document = CrdtText();
    CrdtTextTestUtils.applyChangeToDocument(document, 'Hello', actorId: 'seed');
    final context = CrdtTextTestUtils.editContext('alice', document: document);
    context.insert(0, 'Local ');
    final prepared = context.prepareChange()!;
    final remote = document.fork();
    final change = CrdtTextTestUtils.applyChangeToDocument(
      remote,
      'Hello!',
      actorId: 'bob',
    )!;
    var notifications = 0;
    context.addListener(() => notifications++);

    for (var delivery = 0; delivery < 2; delivery++) {
      document.applyChange(change);
    }

    expect(document.text, 'Hello!');
    expect(context.text, 'Local Hello!');
    expect(context.prepareChange(), same(prepared));
    expect(notifications, 1);
  });

  test('delivery of a local echo acknowledges it', () {
    final document = CrdtText();
    final context = CrdtTextTestUtils.editContext('alice', document: document)
      ..insert(0, 'Hello');
    final prepared = context.prepareChange()!;

    document.applyChange(prepared);

    expect(document.text, 'Hello');
    expect(context.prepareChange(), isNull);
    expect(context.hasPendingChanges, isFalse);
  });
}
