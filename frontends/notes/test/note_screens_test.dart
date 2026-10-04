import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/note_system_provider.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/settings/settings_screen.dart';

import 'package:kv/kv.dart';
import 'package:sync/sync.dart';

import 'support/remote_note_update.dart';

void main() {
  testWidgets('home list updates after an external stored command', (
    tester,
  ) async {
    final store = MemoryEventStore();
    final runtime = CqrsTestRuntime(eventStore: store);
    final application = NotesApp(cqrsRuntime: runtime);
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    await application.command.updateNoteTitle(noteId, 'Before');

    await tester.pumpWidget(
      NotesAppProvider(
        application: application,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsOneWidget);

    await addRemoteTitleUpdate(store, noteId, 'After');
    await tester.pumpAndSettle();

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });

  testWidgets('home list refreshes after saving a new note and returning', (
    tester,
  ) async {
    final application = NotesApp(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      NotesAppProvider(
        application: application,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'After navigation');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('After navigation'), findsOneWidget);
  });

  testWidgets('new note timestamps appear after a successful write', (
    tester,
  ) async {
    final application = NotesApp(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      NotesAppProvider(
        application: application,
        child: const MaterialApp(home: NoteScreen(noteId: null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Created at'), findsNothing);
    expect(find.textContaining('Updated at'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'First title');
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Created at'), findsOneWidget);
    expect(find.textContaining('Updated at'), findsOneWidget);
  });

  testWidgets('home reloads notes when its application provider changes', (
    tester,
  ) async {
    final first = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final firstId = first.generateNoteId();
    await first.command.createNote(firstId);
    await first.command.updateNoteTitle(firstId, 'First application');
    final second = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final secondId = second.generateNoteId();
    await second.command.createNote(secondId);
    await second.command.updateNoteTitle(secondId, 'Second application');

    await tester.pumpWidget(
      NotesAppProvider(
        application: first,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First application'), findsOneWidget);

    await tester.pumpWidget(
      NotesAppProvider(
        application: second,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Second application'), findsOneWidget);
    expect(find.text('First application'), findsNothing);
  });

  testWidgets('note editor uses a replacement application provider', (
    tester,
  ) async {
    final first = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final second = NotesApp(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      NotesAppProvider(
        application: first,
        child: const MaterialApp(home: NoteScreen(noteId: null)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Old draft');

    await tester.pumpWidget(
      NotesAppProvider(
        application: second,
        child: const MaterialApp(home: NoteScreen(noteId: null)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old draft'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'New draft');
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(await first.query.noteList(), isEmpty);
    expect(await second.query.noteList(), hasLength(1));
  });

  testWidgets('settings displays active notes and event count', (tester) async {
    final eventStore = MemoryEventStore();
    final application = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: eventStore),
    );
    await application.command.createNote(application.generateNoteId());
    final trashedId = application.generateNoteId();
    await application.command.createNote(trashedId);
    await application.command.trashNote(trashedId);
    await _pumpSettings(
      tester,
      application: application,
      eventStore: eventStore,
      reset: (_) async {},
    );

    expect(find.text('Active Note Count'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Event Count'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Rerun projections'), findsNothing);
    expect(find.text('Reset database'), findsOneWidget);
  });

  testWidgets('canceling database reset does not reset the database', (
    tester,
  ) async {
    final resets = <bool>[];
    await _pumpSettings(tester, reset: (restart) async => resets.add(restart));

    await tester.ensureVisible(find.text('Reset database'));
    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This deletes all notes, event history, settings, and pairings.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final restart in [false, true]) {
      testWidgets('settings reset with restart=$restart on ${platform.name}', (
        tester,
      ) async {
        final resets = <bool>[];
        await _pumpSettings(
          tester,
          platform: platform,
          reset: (restart) async => resets.add(restart),
        );

        await tester.ensureVisible(find.text('Reset database'));
        await tester.tap(find.text('Reset database'));
        await tester.pumpAndSettle();
        final button = find.widgetWithText(
          TextButton,
          restart ? 'Reset and restart' : 'Reset',
        );
        final enabled = !restart || platform != TargetPlatform.iOS;
        expect(tester.widget<TextButton>(button).enabled, enabled);

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(resets, enabled ? [restart] : isEmpty);
        expect(
          find.byType(AlertDialog),
          enabled ? findsNothing : findsOneWidget,
        );
      });
    }
  }
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  NotesApp? application,
  MemoryEventStore? eventStore,
  TargetPlatform platform = TargetPlatform.iOS,
  required Future<void> Function(bool restart) reset,
}) async {
  final store = eventStore ?? MemoryEventStore();
  await tester.pumpWidget(
    NotesAppProvider(
      application:
          application ??
          NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store)),
      child: NoteSystemProvider(
        system: NoteSystem(
          identities: MemoryActorIdentityStore(),
          kv: MemoryKv(),
          eventStore: store,
        ),
        child: EventStoreProvider(
          eventStore: store,
          reset: reset,
          child: MaterialApp(
            theme: ThemeData(platform: platform),
            home: const SettingsScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
