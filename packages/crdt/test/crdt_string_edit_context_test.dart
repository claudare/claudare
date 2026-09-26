import 'package:crdt/crdt_string.dart';
import 'package:test/test.dart';

void main() {
  late CrdtString document;
  late CrdtStringEditContext context;

  setUp(() {
    document = CrdtString()..applyChange(change('Initial'));
    context = CrdtStringEditContext(document: document, actorId: 'local');
  });
  tearDown(() => context.dispose());

  test('initializes a clean draft from persisted state', () {
    expect(context.value, 'Initial');
    expect(context.hasPendingChanges, isFalse);
    expect(context.prepareChange(), isNull);
  });

  test('local edits leave persisted state unchanged', () {
    context.value = 'Local';
    expect(document.value, 'Initial');
    expect(context.prepareChange(), 'Local');
    expect(context.hasPendingChanges, isTrue);
  });

  test('returning to persisted value before preparation clears the edit', () {
    context.value = 'Local';
    context.value = 'Initial';
    expect(context.prepareChange(), isNull);
  });

  test('empty string is a saveable change', () {
    context.value = '';
    expect(context.prepareChange(), '');
    document.applyChange(change('', actor: 'local', time: 2));
    expect(context.hasPendingChanges, isFalse);
  });

  test('replay updates a clean draft without generating outgoing edits', () {
    document.applyChange(change('Remote', time: 2));
    expect(context.value, 'Remote');
    expect(context.prepareChange(), isNull);
  });

  test('remote updates preserve an unsaved local draft', () {
    context.value = 'Local';
    document.applyChange(change('Remote', time: 2));
    expect(context.value, 'Local');
    expect(document.value, 'Remote');
    expect(context.prepareChange(), 'Local');
  });

  test(
    'preparation retains the original value until replay acknowledges it',
    () {
      context.value = 'First';
      expect(context.prepareChange(), 'First');
      context.value = 'Second';
      expect(context.prepareChange(), 'First');
      document.applyChange(change('First', actor: 'local', time: 2));
      expect(context.value, 'Second');
      expect(context.prepareChange(), 'Second');
      document.applyChange(change('Second', actor: 'local', time: 3));
      expect(context.hasPendingChanges, isFalse);
    },
  );

  test('returning to the old value during saving remains pending', () {
    context.value = 'First';
    context.prepareChange();
    context.value = 'Initial';
    document.applyChange(change('First', actor: 'local', time: 2));
    expect(context.prepareChange(), 'Initial');
  });

  test(
    'same value from another actor does not acknowledge the prepared edit',
    () {
      context.value = 'Local';
      context.prepareChange();
      document.applyChange(change('Local', time: 2));
      expect(context.hasPendingChanges, isTrue);
    },
  );

  test('a losing persisted write is acknowledged and adopts the winner', () {
    context.value = 'Local';
    context.prepareChange();
    document.applyChange(change('Remote', time: 3));
    document.applyChange(change('Local', actor: 'local', time: 2));
    expect(context.value, 'Remote');
    expect(context.hasPendingChanges, isFalse);
  });

  test('duplicate replay does not discard a later local edit', () {
    context.value = 'First';
    context.prepareChange();
    final saved = change('First', actor: 'local', time: 2);
    document.applyChange(saved);
    context.value = 'Second';
    document.applyChange(saved);
    expect(context.prepareChange(), 'Second');
  });

  test('failed listener notification is retried on repeated delivery', () {
    var fail = true;
    final observed = <String>[];
    context.addListener(() {
      if (fail) throw StateError('Interrupted listener');
      observed.add(context.value);
    });
    final remote = change('Remote', time: 2);
    expect(() => document.applyChange(remote), throwsStateError);
    fail = false;
    document.applyChange(remote);
    expect(observed, ['Remote']);
  });

  test('unchanged assignment does not notify listeners', () {
    var calls = 0;
    context.addListener(() => calls++);
    context.value = 'Initial';
    expect(calls, 0);
  });

  test('disposing detaches persisted updates', () {
    context.dispose();
    document.applyChange(change('Remote', time: 2));
    expect(context.value, 'Initial');
  });
}

CrdtStringChange change(
  String value, {
  String actor = 'remote',
  int time = 1,
}) => CrdtStringChange(
  value: value,
  actor: actor,
  time: DateTime.fromMillisecondsSinceEpoch(time),
);
