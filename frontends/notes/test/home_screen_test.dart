import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/screens/home/widget/note_list_item.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:time_provider/time_provider.dart';

import 'support/home_test_app.dart';
import 'support/note_list_test_store.dart';

// these are a bit verbose... sloppy code for now
void main() {
  testWidgets('shows loading until the initial note list is ready', (
    tester,
  ) async {
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final store = NoteListTestStore()..beforeRead = release.future;
    final app = _createApp(store);

    await tester.pumpWidget(
      NotesAppProvider(application: app, child: homeTestApp()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No notes yet'), findsNothing);
    expect(
      tester
          .widget<PopupMenuButton<NoteSortOrder>>(
            find.byType(PopupMenuButton<NoteSortOrder>),
          )
          .enabled,
      isFalse,
    );

    release.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('shows an initial note list replay failure', (tester) async {
    final store = NoteListTestStore()..readFailure = Exception('Read failed');
    final app = _createApp(store);

    await tester.pumpWidget(
      NotesAppProvider(application: app, child: homeTestApp()),
    );
    await _pumpListFailure(tester);

    expect(
      find.text('Error loading notes: Exception: Read failed'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notes yet'), findsNothing);
  });

  testWidgets('shows a live note list replay failure', (tester) async {
    final store = NoteListTestStore();
    final app = _createApp(store);
    await tester.pumpWidget(
      NotesAppProvider(application: app, child: homeTestApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
    store.readFailure = Exception('Read failed');

    await app.command.createNote('one');
    await _pumpListFailure(tester);

    expect(
      find.text('Error loading notes: Exception: Read failed'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notes yet'), findsNothing);
  });

  testWidgets('renders note changes without a navigation refresh', (
    tester,
  ) async {
    final app = _createApp(NoteListTestStore());
    await app.command.createNote('one');
    await app.command.updateNoteTitle('one', 'Original');
    await tester.pumpWidget(
      NotesAppProvider(application: app, child: homeTestApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);

    await app.command.updateNoteTitle('one', 'Updated');
    await tester.pumpAndSettle();

    expect(find.text('Original'), findsNothing);
    expect(find.text('Updated'), findsOneWidget);
  });

  testWidgets('switches category using the already loaded model', (
    tester,
  ) async {
    final store = NoteListTestStore();
    final app = _createApp(store);
    await app.command.createNote('one');
    await app.command.updateNoteTitle('one', 'Trashed note');
    await app.command.trashNote('one');
    await tester.pumpWidget(
      NotesAppProvider(application: app, child: homeTestApp()),
    );
    await tester.pumpAndSettle();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    store.beforeRead = release.future;

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Trash'));
    await tester.pumpAndSettle();

    expect(find.text('Trashed note'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('application replacement clears the previous note list', (
    tester,
  ) async {
    final original = _createApp(NoteListTestStore());
    await original.command.createNote('one');
    await original.command.updateNoteTitle('one', 'Original note');
    await tester.pumpWidget(
      NotesAppProvider(application: original, child: homeTestApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Original note'), findsOneWidget);
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final store = NoteListTestStore()..beforeRead = release.future;
    final replacement = _createApp(store);
    await replacement.command.createNote('two');
    await replacement.command.updateNoteTitle('two', 'Replacement note');

    await tester.pumpWidget(
      NotesAppProvider(application: replacement, child: homeTestApp()),
    );

    expect(find.text('Original note'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    release.complete();
    await tester.pumpAndSettle();

    expect(find.text('Replacement note'), findsOneWidget);
    expect(find.text('Original note'), findsNothing);
  });

  testWidgets('Notes and Trash remain separate when switching and restoring', (
    tester,
  ) async {
    final app = NotesApp(
      cqrsRuntime: CqrsTestRuntime(),
      fts: NoopFts(),
      logger: const NoopLogger(),
    );
    final active = app.generateNoteId();
    final trashed = app.generateNoteId();
    await app.command.createNote(active);
    await app.command.updateNoteTitle(active, 'Active note');
    await app.command.createNote(trashed);
    await app.command.updateNoteTitle(trashed, 'Trashed note');
    await app.command.trashNote(trashed);
    await tester.pumpWidget(
      NotesAppProvider(application: app, child: homeTestApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active note'), findsOneWidget);
    expect(find.text('Trashed note'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Active note'), findsNothing);
    expect(find.text('Trashed note'), findsOneWidget);
    expect(find.byTooltip('New note'), findsNothing);

    await tester.tap(find.text('Trashed note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Trash is empty'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Active note'), findsOneWidget);
    expect(find.text('Trashed note'), findsOneWidget);
  });

  for (final (label, titles, dateLabel) in [
    ('Last edited, newest first', ['First', 'Second'], 'Edited'),
    ('Last edited, oldest first', ['Second', 'First'], 'Edited'),
    ('Created, newest first', ['Second', 'First'], 'Created'),
    ('Created, oldest first', ['First', 'Second'], 'Created'),
  ]) {
    testWidgets('sorts by $label', (tester) async {
      final clock = _Clock();
      final app = NotesApp(
        cqrsRuntime: CqrsTestRuntime(timeProvider: clock),
        fts: NoopFts(),
        logger: const NoopLogger(),
      );
      final first = app.generateNoteId();
      final second = app.generateNoteId();
      await app.command.createNote(first);
      await app.command.updateNoteTitle(first, 'First');
      clock.value = DateTime.utc(2026, 2);
      await app.command.createNote(second);
      await app.command.updateNoteTitle(second, 'Second');
      clock.value = DateTime.utc(2026, 3);
      await app.command.updateNoteTitle(first, 'First');
      Widget buildApp() =>
          NotesAppProvider(application: app, child: homeTestApp());
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort notes'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<NoteSortOrder>, label),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NoteListItem>(find.byType(NoteListItem))
            .map((item) => item.note.title),
        titles,
      );
      expect(find.textContaining('$dateLabel\n'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Sort notes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<NoteSortOrder>>(
              find.widgetWithText(CheckedPopupMenuItem<NoteSortOrder>, label),
            )
            .checked,
        isTrue,
      );
    });
  }
}

Future<void> _pumpListFailure(WidgetTester tester) async {
  // Stream cancellation schedules work outside the widget test clock.
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    if (find.textContaining('Error loading notes:').evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Note list did not report its replay failure');
}

NotesApp _createApp(NoteListTestStore store) => NotesApp(
  cqrsRuntime: CqrsTestRuntime(eventStore: store),
  fts: NoopFts(),
  logger: const NoopLogger(),
);

class _Clock implements TimeProvider {
  DateTime value = DateTime.utc(2026);

  @override
  DateTime now() => value;
}
