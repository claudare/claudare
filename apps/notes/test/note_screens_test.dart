import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/settings/settings_screen.dart';

void main() {
  testWidgets('home list refreshes after saving a new note and returning', (
    tester,
  ) async {
    final application = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(application: application)),
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
    final application = NoteApplication(cqrsRuntime: CqrsTestRuntime());
    await tester.pumpWidget(
      MaterialApp(home: NoteScreen(application: application, noteId: null)),
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

  testWidgets('settings displays active notes and event count', (tester) async {
    final eventStore = EventStore(MemoryEventDatabase());
    final application = NoteApplication(
      cqrsRuntime: CqrsTestRuntime(eventStore: eventStore),
    );
    await application.command.createNote();
    final trashedId = await application.command.createNote();
    await application.command.trashNote(trashedId);
    var resets = 0;

    await tester.pumpWidget(
      NoteApplicationProvider(
        application: application,
        child: EventStoreProvider(
          eventStore: eventStore,
          reset: () async => resets++,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active Note Count'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Event Count'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Rerun projections'), findsNothing);
    expect(find.text('Reset database'), findsOneWidget);

    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Close and reopen Notes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);

    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(resets, 1);
  });
}
