import 'package:crdt/crdt_string.dart';
import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

import 'text/text_test_support.dart';

void main() {
  late CrdtString document;
  late CrdtStringEditContext context;
  late FakeTextController controller;
  late CrdtStringBinding binding;

  void remote(String value) => document.applyChange(
    CrdtStringChange(
      value: value,
      actor: 'remote',
      time: DateTime.fromMillisecondsSinceEpoch(2),
    ),
  );

  setUp(() {
    document = CrdtString()
      ..applyChange(
        CrdtStringChange(
          value: 'Title',
          actor: 'remote',
          time: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      );
    context = CrdtStringEditContext(document: document, actorId: 'local');
    controller = FakeTextController();
    binding = CrdtStringBinding(editContext: context, controller: controller);
  });
  tearDown(() {
    binding.dispose();
    context.dispose();
  });

  test('initializes the editor from the draft', () {
    expect(controller.value.text, 'Title');
    expect(controller.value.selectionExtent, 5);
    expect(context.hasPendingChanges, isFalse);
  });

  test('editor replacements update only the local draft', () {
    controller.edit('Local', 5);
    expect(context.prepareChange(), 'Local');
    expect(document.value, 'Title');
    expect(controller.assignments, 2);
  });

  test('remote replacement clamps selection and retains its direction', () {
    controller.value = CrdtTextEditingValue(
      text: 'Title',
      selectionBase: 5,
      selectionExtent: 1,
      affinity: CrdtTextAffinity.upstream,
      isDirectional: true,
    );
    remote('Hi');
    expect(controller.value.text, 'Hi');
    expect(controller.value.selectionBase, 2);
    expect(controller.value.selectionExtent, 1);
    expect(controller.value.affinity, CrdtTextAffinity.upstream);
    expect(controller.value.isDirectional, isTrue);
    expect(context.prepareChange(), isNull);
  });

  test('selection and composition alone create no pending edits', () {
    controller.edit('Title', 1);
    controller.edit('Title', 2, composingStart: 1, composingEnd: 2);
    controller.edit('Title', 2);
    expect(context.prepareChange(), isNull);
  });

  test('remote refresh waits for composition to end', () {
    controller.edit('Title', 2, composingStart: 1, composingEnd: 2);
    remote('Remote');
    expect(controller.value.text, 'Title');
    controller.edit('Title', 2);
    expect(controller.value.text, 'Remote');
    expect(context.prepareChange(), isNull);
  });

  test('local composing edits survive remote replacements', () {
    controller.edit('日本', 2, composingStart: 0, composingEnd: 2);
    remote('Remote');
    controller.edit('日本語', 3);
    expect(context.prepareChange(), '日本語');
    expect(controller.value.text, '日本語');
  });

  test('disposal detaches both directions', () {
    binding.dispose();
    remote('Remote');
    expect(controller.value.text, 'Title');
    controller.edit('Local', 5);
    expect(context.value, 'Remote');
    expect(controller.listeners, isEmpty);
  });
}
