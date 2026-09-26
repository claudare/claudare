import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/event/note.dart';

void main() {
  testWidgets('navigation saves a new content-only note', (tester) async {
    final app = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      NoteApplicationProvider(
        application: app,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'New content');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    final notes = (await app.query.noteList()).notes;
    expect(notes, hasLength(1));
    expect(notes.values.single.content, 'New content');
  });

  testWidgets('application replacement detaches the previous content draft', (
    tester,
  ) async {
    final first = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    final second = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    for (final app in [first, second]) {
      await tester.pumpWidget(
        NoteApplicationProvider(
          application: app,
          child: const MaterialApp(home: NoteScreen(noteId: null)),
        ),
      );
      await tester.pumpAndSettle();
      expect(_content(tester).text, '');
      await tester.enterText(find.byType(TextField).last, 'Draft');
    }
    await _save(tester);
    expect((await first.query.noteList()).notes, isEmpty);
    expect(
      (await second.query.noteList()).notes.values.single.content,
      'Draft',
    );
  });

  testWidgets('successive UI edits persist and reopen with their actor', (
    tester,
  ) async {
    final app = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    final id = await app.command.createNote();
    await _open(tester, app, id);
    for (final text in ['Hello', 'Hello world', 'Hello 🌍', '🌍', '']) {
      await tester.enterText(find.byType(TextField).last, text);
      await _save(tester);
      expect((await app.query.note(id))!.content, text);
    }
    final events = await _contentEvents(app, id);
    expect(events, hasLength(5));
    expect(events.every((event) => event.change.actorId == app.actor), isTrue);
    await _reopen(tester, app, id);
    expect(_content(tester).text, '');
  });

  testWidgets('refresh merges external edits with an unsaved UI draft', (
    tester,
  ) async {
    final app = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    final id = await app.command.createNote();
    await app.command.simulateExternalNoteContentEdit(
      id,
      'Base',
      actorId: 'remote',
    );
    await _open(tester, app, id);
    await tester.enterText(find.byType(TextField).last, 'Local Base');
    await app.command.simulateExternalNoteContentEdit(
      id,
      'Base one',
      actorId: 'remote',
    );
    await app.command.simulateExternalNoteContentEdit(
      id,
      'Base one two',
      actorId: 'remote',
    );
    expect(_content(tester).text, 'Local Base');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(_content(tester).text, 'Local Base one two');
    expect((await app.query.note(id))!.content, 'Base one two');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(await _contentEvents(app, id), hasLength(3));
    await _save(tester);
    await _reopen(tester, app, id);
    expect(_content(tester).text, 'Local Base one two');
  });

  testWidgets('refresh adjusts the selection around an external insertion', (
    tester,
  ) async {
    final app = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    final id = await app.command.createNote();
    await app.command.simulateExternalNoteContentEdit(
      id,
      'abc',
      actorId: 'remote',
    );
    await _open(tester, app, id);
    _content(tester).selection = const TextSelection.collapsed(offset: 2);
    await app.command.simulateExternalNoteContentEdit(
      id,
      'Xabc',
      actorId: 'remote',
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(_content(tester).selection.baseOffset, 3);
  });

  testWidgets('refresh waits for composition before updating the field', (
    tester,
  ) async {
    final app = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    final id = await app.command.createNote();
    await app.command.simulateExternalNoteContentEdit(
      id,
      'abc',
      actorId: 'remote',
    );
    await _open(tester, app, id);
    final controller = _content(tester);
    controller.value = const TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 1, end: 3),
    );
    await app.command.simulateExternalNoteContentEdit(
      id,
      'Xabc',
      actorId: 'remote',
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(controller.text, 'abc');
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.pump();
    expect(controller.text, 'Xabc');
  });

  testWidgets('failed content save retries the prepared batch', (tester) async {
    final store = _ControlledStore();
    final app = NoteApplication(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
    );
    final id = await app.command.createNote();
    await _open(tester, app, id);
    await tester.enterText(find.byType(TextField).last, 'Draft');
    store.failNext = true;
    await _save(tester);
    expect((await app.query.note(id))!.content, '');
    expect(find.textContaining('Error saving note'), findsOneWidget);
    await tester.tap(find.byType(TextField).last);
    await _save(tester);
    expect((await app.query.note(id))!.content, 'Draft');
    expect(await _contentEvents(app, id), hasLength(1));
  });

  testWidgets('edits during saving are persisted in a subsequent batch', (
    tester,
  ) async {
    final store = _ControlledStore();
    final app = NoteApplication(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
    );
    final id = await app.command.createNote();
    await _open(tester, app, id);
    await tester.enterText(find.byType(TextField).last, 'First');
    final gate = Completer<void>();
    store.gate = gate.future;
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'First second');
    gate.complete();
    await tester.pumpAndSettle();
    final note = (await app.query.note(id))!;
    expect(note.content, 'First second');
    expect(await _contentEvents(app, id), hasLength(2));
  });

  testWidgets('selection changes and unchanged saves emit no content events', (
    tester,
  ) async {
    final app = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    final id = await app.command.createNote();
    await _open(tester, app, id);
    await tester.tap(find.byType(TextField).last);
    await _save(tester);
    expect(await _contentEvents(app, id), isEmpty);
  });
}

TextEditingController _content(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!;

Future<List<NoteContentUpdated>> _contentEvents(
  NoteApplication app,
  String id,
) async =>
    (await app.query.noteEvents(id).toList())
        .map((delivery) => delivery.envelope.event)
        .whereType<NoteContentUpdated>()
        .toList();

Future<void> _open(WidgetTester tester, NoteApplication app, String id) async {
  await tester.pumpWidget(
    NoteApplicationProvider(
      application: app,
      child: MaterialApp(home: NoteScreen(noteId: id)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reopen(
  WidgetTester tester,
  NoteApplication app,
  String id,
) async {
  await tester.pumpWidget(const SizedBox());
  await _open(tester, app, id);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byType(TextField).first);
  await tester.pumpAndSettle();
}

class _ControlledStore extends MemoryEventStore {
  bool failNext = false;
  Future<void>? gate;

  @override
  Future<void> saveChanges(changes) async {
    if (failNext) {
      failNext = false;
      throw Exception('Test write failure');
    }
    final waiting = gate;
    gate = null;
    await waiting;
    await super.saveChanges(changes);
  }
}
