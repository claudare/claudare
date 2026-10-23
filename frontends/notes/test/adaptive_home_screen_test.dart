import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/layout_breakpoints.dart';
import 'package:notes/screens/home/widget/note_list.dart';
import 'package:notes/screens/settings/settings_screen.dart';
import 'package:notes_app/notes_app.dart';

import 'support/home_test_app.dart';

void main() {
  for (final width in [
    320.0,
    LayoutBreakpoints.wide - 1,
    LayoutBreakpoints.wide,
    LayoutBreakpoints.wide + 300,
  ]) {
    testWidgets('navigation adapts at width $width', (tester) async {
      await _pumpHome(tester, width);
      final wide = width >= LayoutBreakpoints.wide;
      expect(
        find.byTooltip('Open navigation menu'),
        wide ? findsNothing : findsOneWidget,
      );
      expect(
        find.widgetWithText(ListTile, 'Settings'),
        wide ? findsOneWidget : findsNothing,
      );
      expect(tester.getTopLeft(find.byType(AppBar)).dx, wide ? 280 : 0);
      expect(
        tester.getCenter(find.byTooltip('Sort notes')).dx,
        lessThan(tester.getCenter(find.byTooltip('New note')).dx),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [400.0, LayoutBreakpoints.wide]) {
    testWidgets('Settings opens and returns at width $width', (tester) async {
      await _pumpHome(tester, width);
      final wide = width >= LayoutBreakpoints.wide;
      if (!wide) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(ListTile, 'Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Trash'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('No notes yet'), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Settings'),
        wide ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('resizing preserves category, order, and scroll position', (
    tester,
  ) async {
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
    for (var i = 0; i < 40; i++) {
      final id = app.generateNoteId();
      await app.command.createNote(id);
      await app.command.updateNoteTitle(id, 'Note $i');
      await app.command.trashNote(id);
    }
    await _pumpHome(tester, LayoutBreakpoints.wide, application: app);
    await tester.tap(find.widgetWithText(ListTile, 'Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sort notes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<NoteSortOrder>,
        'Created, oldest first',
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(NoteList), const Offset(0, -500));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(NoteList),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    final initialOffset = offset();
    expect(initialOffset, greaterThan(0));

    for (final width in [400.0, LayoutBreakpoints.wide]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpAndSettle();
      final list = tester.widget<NoteList>(find.byType(NoteList));
      expect(list.noteData.every((note) => note.isTrashed), isTrue);
      expect(list.order, NoteSortOrder.createdAtAscending);
      expect(offset(), closeTo(initialOffset, 0.1));
      expect(find.byTooltip('New note'), findsNothing);
    }
  });

  testWidgets('resizing an open drawer leaves no overlay or navigation entry', (
    tester,
  ) async {
    await _pumpHome(tester, 400);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = Size(LayoutBreakpoints.wide, 600);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.widgetWithText(ListTile, 'Trash'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );

    tester.view.physicalSize = const Size(400, 600);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Trash'), findsNothing);
    expect(
      tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
      isFalse,
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Trash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpHome(
  WidgetTester tester,
  double width, {
  NotesApp? application,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NotesAppProvider(
      application: application ?? NotesApp(cqrsRuntime: CqrsTestRuntime()),
      child: homeTestApp(),
    ),
  );
  await tester.pumpAndSettle();
}
