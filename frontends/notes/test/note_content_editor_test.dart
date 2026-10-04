import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/home/home_screen.dart';

import 'support/remote_note_update.dart';

void main() {
  testWidgets(
    'title binding displays replayed updates without writing them back',
    (tester) async {
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
      final id = app.generateNoteId();
      await app.command.createNote(id);
      await _open(tester, app, id);
      await app.command.updateNoteTitle(id, 'Remote title');
      await tester.pumpAndSettle();
      final editor = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      expect(editor.text, 'Remote title');
      await tester.tap(find.byType(TextField).first);
      await _pressSaveShortcut(tester);
      await tester.pumpAndSettle();
      expect(find.text('Nothing to save'), findsOneWidget);
      expect((await app.query.note(id)).title, 'Remote title');
    },
  );

  testWidgets('open note updates after an external stored command', (
    tester,
  ) async {
    final store = MemoryEventStore();
    final runtime = CqrsTestRuntime(eventStore: store);
    final app = NotesApp(cqrsRuntime: runtime);
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await _open(tester, app, id);
    await addRemoteTitleUpdate(store, id, 'External title');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'External title',
    );
  });

  testWidgets('title edits made during saving persist in a subsequent batch', (
    tester,
  ) async {
    final store = _ControlledStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await _open(tester, app, id);
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'First');
    final gate = Completer<void>();
    store.gate = gate.future;
    await _pressSaveShortcut(tester);
    await tester.pump();
    await tester.enterText(field, 'Second');
    gate.complete();
    await tester.pumpAndSettle();
    expect((await app.query.note(id)).title, 'Second');
    expect(tester.widget<TextField>(field).controller!.text, 'Second');
  });

  for (final (fieldIndex, value) in [(0, 'Shortcut title'), (1, 'Body')]) {
    testWidgets('Ctrl+S saves field $fieldIndex without moving focus', (
      tester,
    ) async {
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
      await tester.pumpWidget(
        NotesAppProvider(
          application: app,
          child: const MaterialApp(home: NoteScreen(noteId: null)),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byType(TextField).at(fieldIndex);
      await tester.enterText(field, value);
      await _pressSaveShortcut(tester);
      await tester.pumpAndSettle();

      final notes = await app.query.noteList();
      expect(notes, hasLength(1));
      expect(
        fieldIndex == 0 ? notes.single.title : notes.single.content,
        value,
      );
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    });
  }

  for (final existing in [false, true]) {
    testWidgets('Ctrl+S reports nothing to save for existing=$existing', (
      tester,
    ) async {
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
      final id = existing ? app.generateNoteId() : null;
      if (id != null) await app.command.createNote(id);
      await _open(tester, app, id);
      await tester.tap(find.byType(TextField).first);

      await _pressSaveShortcut(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nothing to save'), findsOneWidget);
      expect(await app.query.noteList(), hasLength(existing ? 1 : 0));
    });
  }

  testWidgets(
    'saving a draft after deleting all content finishes without creating it',
    (tester) async {
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
      await _open(tester, app, null);
      final field = find.byType(TextField).last;
      await tester.enterText(field, 'Temporary content');
      await tester.enterText(field, '');

      await _pressSaveShortcut(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nothing to save'), findsOneWidget);
      expect(await app.query.noteList(), isEmpty);
    },
  );

  testWidgets('navigation saves a new content-only note', (tester) async {
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      NotesAppProvider(
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
    final notes = await app.query.noteList();
    expect(notes, hasLength(1));
    expect(notes.single.content, 'New content');
  });

  testWidgets('application replacement detaches the previous content draft', (
    tester,
  ) async {
    final first = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final second = NotesApp(cqrsRuntime: CqrsTestRuntime());
    for (final app in [first, second]) {
      await tester.pumpWidget(
        NotesAppProvider(
          application: app,
          child: const MaterialApp(home: NoteScreen(noteId: null)),
        ),
      );
      await tester.pumpAndSettle();
      expect(_content(tester).text, '');
      await tester.enterText(find.byType(TextField).last, 'Draft');
    }
    await _save(tester);
    expect(await first.query.noteList(), isEmpty);
    expect((await second.query.noteList()).single.content, 'Draft');
  });

  testWidgets('successive UI edits persist and reopen with their actor', (
    tester,
  ) async {
    final store = MemoryEventStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await _open(tester, app, id);
    for (final text in ['Hello', 'Hello world', 'Hello 🌍', '🌍', '']) {
      await tester.enterText(find.byType(TextField).last, text);
      await _save(tester);
      expect((await app.query.note(id)).content, text);
    }
    final events = (await store.getLogEvents(0)).data;
    expect(events, hasLength(6));
    expect(
      events.skip(1).every((event) => event.eventId.actor == app.actor),
      isTrue,
    );
    await _reopen(tester, app, id);
    expect(_content(tester).text, '');
  });

  testWidgets('external edits merge automatically with an unsaved UI draft', (
    tester,
  ) async {
    final store = MemoryEventStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await app.command.testSimulateExternalNoteContentAppend(
      id,
      'Base',
      actorId: 'remote',
    );
    await _open(tester, app, id);
    await tester.enterText(find.byType(TextField).last, 'Local Base');
    await app.command.testSimulateExternalNoteContentAppend(
      id,
      ' one',
      actorId: 'remote',
    );
    await app.command.testSimulateExternalNoteContentAppend(
      id,
      ' two',
      actorId: 'remote',
    );
    await tester.pumpAndSettle();
    expect(_content(tester).text, 'Local Base one two');
    expect((await app.query.note(id)).content, 'Base one two');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(await EventStoreTestUtils.getEventCount(store), 4);
    await _save(tester);
    await _reopen(tester, app, id);
    expect(_content(tester).text, 'Local Base one two');
  });

  testWidgets('automatic refresh preserves selection before appended text', (
    tester,
  ) async {
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await app.command.testSimulateExternalNoteContentAppend(
      id,
      'abc',
      actorId: 'remote',
    );
    await _open(tester, app, id);
    _content(tester).selection = const TextSelection.collapsed(offset: 2);
    await app.command.testSimulateExternalNoteContentAppend(
      id,
      'X',
      actorId: 'remote',
    );
    await tester.pumpAndSettle();
    expect(_content(tester).selection.baseOffset, 2);
  });

  testWidgets('automatic refresh waits for composition before field update', (
    tester,
  ) async {
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await app.command.testSimulateExternalNoteContentAppend(
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
    await app.command.testSimulateExternalNoteContentAppend(
      id,
      'X',
      actorId: 'remote',
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'abc');
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.pump();
    expect(controller.text, 'abcX');
  });

  testWidgets('failed content save retries the prepared batch', (tester) async {
    final store = _ControlledStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await _open(tester, app, id);
    await tester.enterText(find.byType(TextField).last, 'Draft');
    store.failNext = true;
    await _save(tester);
    expect((await app.query.note(id)).content, '');
    expect(find.textContaining('Error saving note'), findsOneWidget);
    await tester.tap(find.byType(TextField).last);
    await _save(tester);
    expect((await app.query.note(id)).content, 'Draft');
    expect(await EventStoreTestUtils.getEventCount(store), 2);
  });

  testWidgets('edits during saving are persisted in a subsequent batch', (
    tester,
  ) async {
    final store = _ControlledStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await _open(tester, app, id);
    await tester.enterText(find.byType(TextField).last, 'First');
    final gate = Completer<void>();
    store.gate = gate.future;
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'First second');
    gate.complete();
    await tester.pumpAndSettle();
    final note = await app.query.note(id);
    expect(note.content, 'First second');
    expect(await EventStoreTestUtils.getEventCount(store), 3);
  });

  testWidgets('selection changes and unchanged saves emit no content events', (
    tester,
  ) async {
    final store = MemoryEventStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    await _open(tester, app, id);
    await tester.tap(find.byType(TextField).last);
    await _save(tester);
    expect(await EventStoreTestUtils.getEventCount(store), 1);
  });
}

TextEditingController _content(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!;

Future<void> _open(WidgetTester tester, NotesApp app, String? id) async {
  await tester.pumpWidget(
    NotesAppProvider(
      application: app,
      child: MaterialApp(home: NoteScreen(noteId: id)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pressSaveShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<void> _reopen(WidgetTester tester, NotesApp app, String id) async {
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
