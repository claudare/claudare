import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/screens/home/widget/note_list_item.dart';
import 'package:notes_app/notes_app.dart';
import 'package:time_provider/time_provider.dart';

import 'support/home_test_app.dart';

// these are a bit verbose... sloppy code for now
void main() {
  testWidgets('Notes and Trash remain separate when switching and restoring', (
    tester,
  ) async {
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
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
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime(timeProvider: clock));
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

class _Clock implements TimeProvider {
  DateTime value = DateTime.utc(2026);

  @override
  DateTime now() => value;
}
