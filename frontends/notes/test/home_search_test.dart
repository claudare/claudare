import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/layout_breakpoints.dart';
import 'package:notes/screens/home/note_search_view.dart';
import 'package:notes/screens/home/widget/note_list.dart';
import 'package:notes/screens/home/widget/note_list_item.dart';
import 'package:notes/screens/note/note_screen.dart';
import 'package:notes/screens/settings/settings_screen.dart';
import 'package:notes_app/notes_app.dart';

import 'support/home_test_app.dart';
import 'support/remote_note_update.dart';
import 'support/search_test_app.dart';

void main() {
  testWidgets('search spans Notes and Trash in relevance order', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('active', 'note');
    await fixture.write('trashed', 'note notebook', trashed: true);
    await _pumpHome(tester, fixture);
    await _search(tester, 'note');

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(SearchBar),
      ),
      findsOneWidget,
    );
    expect(find.byType(NoteSearchView), findsOneWidget);
    expect(find.byType(NoteList), findsOneWidget);
    expect(_titles(tester), ['trashed', 'active']);
    expect(find.text('In Trash'), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<NoteSortOrder>>(
            find.byType(PopupMenuButton<NoteSortOrder>),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('search matches contents rather than titles', (tester) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'different contents', title: 'Needle');
    await _pumpHome(tester, fixture);
    await _search(tester, 'needle');
    expect(find.text('No matching notes'), findsOneWidget);
    expect(find.text('Needle'), findsNothing);
    expect(find.text('Search note contents'), findsOneWidget);
  });

  testWidgets('clearing restores the selected section and date order', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('active', 'note notebook');
    await fixture.write('trashed', 'note', trashed: true);
    await _pumpHome(tester, fixture);
    await _selectSection(tester, 'Trash');
    await tester.tap(find.byTooltip('Sort notes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<NoteSortOrder>,
        'Created, oldest first',
      ),
    );
    await tester.pumpAndSettle();
    await _search(tester, 'note');
    expect(_titles(tester), ['active', 'trashed']);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.byType(NoteSearchView), findsNothing);
    final list = tester.widget<NoteList>(find.byType(NoteList));
    expect(list.noteData.map((note) => note.noteId), ['trashed']);
    expect(list.order, NoteSortOrder.createdAtAscending);
    expect(find.text('In Trash'), findsNothing);
    expect(_searchText(tester), isEmpty);
    expect(
      tester
          .widget<PopupMenuButton<NoteSortOrder>>(
            find.byType(PopupMenuButton<NoteSortOrder>),
          )
          .enabled,
      isTrue,
    );
  });

  for (final section in ['Notes', 'Trash']) {
    testWidgets('selecting $section clears the query', (tester) async {
      final fixture = SearchTestApp();
      await fixture.write('active', 'note');
      await fixture.write('trashed', 'note', trashed: true);
      await _pumpHome(tester, fixture);
      await _search(tester, 'note');
      await _selectSection(tester, section);
      expect(_searchText(tester), isEmpty);
      expect(find.byType(NoteSearchView), findsNothing);
      expect(_titles(tester), [section == 'Notes' ? 'active' : 'trashed']);
    });
  }

  testWidgets('typing a query keeps the search field mounted and focused', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    await _pumpHome(tester, fixture);
    final field = tester.element(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'note');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.element(find.byType(TextField)), same(field));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('resizing preserves the query and cached results', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    await _pumpHome(tester, fixture);
    await _search(tester, 'note');
    final results = tester.widget<NoteList>(find.byType(NoteList)).noteData;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [LayoutBreakpoints.wide, 400.0, 320.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpAndSettle();
      expect(_searchText(tester), 'note');
      expect(
        tester.widget<NoteList>(find.byType(NoteList)).noteData,
        same(results),
      );
      expect(fixture.fts.queries, ['note']);
    }
  });

  for (final (section, trashed) in [('Notes', true), ('Trash', false)]) {
    testWidgets(
      'opening a ${trashed ? 'trashed' : 'normal'} match returns to $section',
      (tester) async {
        final fixture = SearchTestApp();
        await fixture.write('active', 'unrelated');
        await fixture.write('trashed', 'unrelated', trashed: true);
        await fixture.write('one', 'note', trashed: trashed);
        await _pumpHome(tester, fixture);
        await _selectSection(tester, section);
        await _selectOrder(tester, 'Created, oldest first');
        final originalTitles = _titles(tester).toList();
        await _search(tester, 'note');
        await tester.tap(find.text('one'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<NoteScreen>(find.byType(NoteScreen)).noteId,
          'one',
        );
        expect(
          find.text(trashed ? 'Viewing trashed note' : 'Editing note'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        _expectSearchCleared(tester);
        expect(_titles(tester), originalTitles);
        expect(
          tester.widget<NoteList>(find.byType(NoteList)).order,
          NoteSortOrder.createdAtAscending,
        );
        expect(fixture.fts.queries, ['note']);
      },
    );
  }

  testWidgets('editing a search match returns to the updated normal list', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note', title: 'Before');
    await _pumpHome(tester, fixture);
    await _search(tester, 'note');
    await tester.tap(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Updated');
    await tester.enterText(find.byType(TextField).last, 'replacement');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    _expectSearchCleared(tester);
    expect(_titles(tester), ['Updated']);
    expect(
      tester.widget<NoteList>(find.byType(NoteList)).noteData.single.content,
      'replacement',
    );
    expect(fixture.fts.queries, ['note']);
    await _search(tester, 'replacement');
    expect(_titles(tester), ['Updated']);
    expect(fixture.fts.queries, ['note', 'replacement']);
  });

  testWidgets('New note clears search before opening the editor', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    await _pumpHome(tester, fixture);
    await _search(tester, 'note');
    final searchText = tester
        .widget<SearchBar>(find.byType(SearchBar))
        .controller!;
    await tester.tap(find.byTooltip('New note'));
    await tester.pumpAndSettle();
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).noteId, isNull);
    expect(searchText.text, isEmpty);
    expect(find.byType(NoteSearchView, skipOffstage: false), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    _expectSearchCleared(tester);
    expect(_titles(tester), ['one']);
    expect(fixture.fts.queries, ['note']);
  });

  for (final width in [400.0, LayoutBreakpoints.wide]) {
    testWidgets('Settings clears search at width $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = SearchTestApp();
      await fixture.write('active', 'note');
      await fixture.write('trashed', 'note', trashed: true);
      await _pumpHome(tester, fixture);
      await _selectSection(tester, 'Trash');
      await _selectOrder(tester, 'Created, oldest first');
      await _search(tester, 'note');
      await _selectSection(tester, 'Settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      _expectSearchCleared(tester);
      expect(_titles(tester), ['trashed']);
      expect(
        tester.widget<NoteList>(find.byType(NoteList)).order,
        NoteSortOrder.createdAtAscending,
      );
      expect(fixture.fts.queries, ['note']);
    });
  }

  testWidgets('incoming changes keep snapshots until the query changes', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note', title: 'Before');
    await _pumpHome(tester, fixture);
    await _search(tester, 'note');
    final snapshot = tester.widget<NoteList>(find.byType(NoteList)).noteData;
    await addRemoteTitleUpdate(fixture.store, 'one', 'Remote title');
    await tester.pumpAndSettle();
    expect(
      tester.widget<NoteList>(find.byType(NoteList)).noteData,
      same(snapshot),
    );
    expect(_titles(tester), ['Before']);
    expect(fixture.fts.queries, ['note']);
    await _search(tester, 'not');
    expect(_titles(tester), ['Remote title']);
    expect(fixture.fts.queries, ['note', 'not']);
  });

  testWidgets('index updates do not add new matches to a snapshot', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    await _pumpHome(tester, fixture);
    await _search(tester, 'note');
    await fixture.write('two', 'note notebook');
    await tester.pumpAndSettle();
    expect(_titles(tester), ['one']);
    expect(fixture.fts.queries, ['note']);
    await _search(tester, 'not');
    expect(_titles(tester), ['two', 'one']);
  });

  testWidgets(
    'search loading hides normal notes while projection readiness is pending',
    (tester) async {
      final store = ProjectionLoadingStore();
      final fixture = SearchTestApp(store: store);
      await fixture.write('one', 'note');
      await fixture.write('two', 'unrelated');
      await _pumpHome(tester, fixture, settle: false);
      await pumpSearchProjection(tester, fixture);
      expect(_titles(tester), ['one', 'two']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Loading search'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'note');
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.fts.queries, isEmpty);
      expect(find.byType(NoteList), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading search'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final loading = find.ancestor(
        of: find.text('Loading search'),
        matching: find.byType(Center),
      );
      expect(loading, findsOneWidget);
      expect(
        tester.getCenter(loading),
        tester.getCenter(find.byType(NoteSearchView)),
      );
      final response = Completer<List<String>>();
      fixture.fts.onQuery = (_) => response.future;
      store.loading.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.fts.queries, ['note']);
      expect(find.text('Loading search'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No matching notes'), findsNothing);
      expect(find.byType(NoteList), findsNothing);
      response.complete(['one']);
      await tester.pumpAndSettle();
      expect(_titles(tester), ['one']);
      expect(fixture.fts.queries, ['note']);
      expect(find.text('Loading search'), findsNothing);
    },
  );

  testWidgets(
    'readiness failures affect search without blocking normal notes',
    (tester) async {
      final store = ProjectionLoadingStore();
      final fixture = SearchTestApp(store: store);
      await fixture.write('one', 'note');
      fixture.projectionsDone.ignore();
      await tester.pumpWidget(
        NotesAppProvider(
          application: fixture.application,
          child: homeTestApp(),
        ),
      );
      await pumpSearchProjection(tester, fixture);
      expect(_titles(tester), ['one']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      store.loading.completeError(Exception('Projection unavailable'));
      await pumpSearchCompletion(
        tester,
        expectLater(fixture.application.query.searchReady, throwsException),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_titles(tester), ['one']);
      await _search(tester, 'note');
      expect(find.text('Unable to search notes'), findsOneWidget);
      expect(find.text('Loading search'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await pumpSearchCompletion(
        tester,
        expectLater(fixture.application.stopProjections(), throwsException),
      );
    },
  );

  testWidgets('ready searches hide the startup indicator while queries run', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    await _pumpHome(tester, fixture);
    final response = Completer<List<String>>();
    fixture.fts.onQuery = (_) => response.future;
    await tester.enterText(find.byType(TextField), 'note');
    await tester.pump();
    expect(find.byType(NoteSearchView), findsOneWidget);
    expect(find.byType(NoteList), findsNothing);
    expect(find.text('No matching notes'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Loading search'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Loading search'), findsNothing);
    response.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No matching notes'), findsOneWidget);
    expect(find.text('Loading search'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final previousQuery in ['note', 'missing']) {
    testWidgets('retains "$previousQuery" results while searching again', (
      tester,
    ) async {
      final fixture = SearchTestApp();
      await fixture.write('one', 'note');
      await fixture.write('two', 'other');
      await _pumpHome(tester, fixture);
      await _search(tester, previousQuery);
      final controller = tester
          .widget<NoteSearchView>(find.byType(NoteSearchView))
          .controller;
      final snapshot = controller.results;
      final previousResults = previousQuery == 'note'
          ? find.byType(NoteList)
          : find.text('No matching notes');
      final element = tester.element(previousResults);
      final position = tester.getTopLeft(previousResults);
      final response = Completer<List<String>>();
      fixture.fts.onQuery = (_) => response.future;

      await tester.enterText(find.byType(TextField), 'other');
      await tester.pump();
      expect(controller.results, same(snapshot));
      expect(tester.element(previousResults), same(element));
      expect(tester.getTopLeft(previousResults), position);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Loading search'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(fixture.fts.queries, [previousQuery, 'other']);

      await tester.pump(const Duration(seconds: 1));
      expect(fixture.fts.queries, [previousQuery, 'other']);
      expect(controller.results, same(snapshot));
      expect(tester.element(previousResults), same(element));
      expect(tester.getTopLeft(previousResults), position);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Loading search'), findsNothing);

      response.complete(['two']);
      await tester.pumpAndSettle();
      expect(_titles(tester), ['two']);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Loading search'), findsNothing);
    });
  }

  testWidgets('search failures display a generic message', (tester) async {
    final fixture = SearchTestApp();
    await _pumpHome(tester, fixture);
    fixture.fts.onQuery = (_) => Future.error(Exception('Internal details'));
    await _search(tester, 'note');
    expect(find.text('Unable to search notes'), findsOneWidget);
    expect(find.textContaining('Internal details'), findsNothing);
  });

  testWidgets(
    'application replacement skips queued searches from the old application',
    (tester) async {
      final first = SearchTestApp();
      await first.write('old', 'note');
      await _pumpHome(tester, first);
      await tester.enterText(find.byType(TextField), 'note');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'queued');
      await tester.pump();

      final second = SearchTestApp();
      await second.write('new', 'note');
      await _pumpHome(tester, second);
      expect(_searchText(tester), isEmpty);
      expect(_titles(tester), ['new']);
      expect(first.fts.queries, ['note']);
      await _search(tester, 'note');
      expect(_titles(tester), ['new']);
      expect(second.fts.queries, ['note']);
    },
  );

  testWidgets(
    'application replacement ignores in-flight errors from the old application',
    (tester) async {
      final first = SearchTestApp();
      await first.write('old', 'note');
      await _pumpHome(tester, first);
      final response = Completer<List<String>>();
      first.fts.onQuery = (_) => response.future;
      await tester.enterText(find.byType(TextField), 'note');
      await tester.pump();

      final second = SearchTestApp();
      await second.write('new', 'note');
      await _pumpHome(tester, second);
      response.completeError(Exception('Old application'));
      await tester.pumpAndSettle();
      expect(_searchText(tester), isEmpty);
      expect(_titles(tester), ['new']);
      expect(first.fts.queries, ['note']);
      await _search(tester, 'note');
      expect(_titles(tester), ['new']);
      expect(second.fts.queries, ['note']);
    },
  );

  testWidgets('disposing the screen skips queued throttle work', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await _pumpHome(tester, fixture);
    await tester.enterText(find.byType(TextField), 'note');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'queued');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.fts.queries, ['note']);
  });
}

Future<void> _pumpHome(
  WidgetTester tester,
  SearchTestApp fixture, {
  bool settle = true,
}) async {
  unawaited(fixture.projectionsDone);
  addTearDown(() async {
    await pumpSearchCompletion(tester, fixture.application.stopProjections());
  });
  await tester.pumpWidget(
    NotesAppProvider(application: fixture.application, child: homeTestApp()),
  );
  if (settle) {
    await pumpSearchProjection(tester, fixture);
    await tester.pumpAndSettle();
  }
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  if (find.byTooltip('Open navigation menu').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.widgetWithText(ListTile, label));
  await tester.pumpAndSettle();
}

Future<void> _selectOrder(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Sort notes'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(CheckedPopupMenuItem<NoteSortOrder>, label),
  );
  await tester.pumpAndSettle();
}

void _expectSearchCleared(WidgetTester tester) {
  expect(_searchText(tester), isEmpty);
  expect(find.byType(NoteSearchView), findsNothing);
  expect(find.byTooltip('Clear search'), findsNothing);
  expect(
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
    isFalse,
  );
  expect(
    tester
        .widget<PopupMenuButton<NoteSortOrder>>(
          find.byType(PopupMenuButton<NoteSortOrder>),
        )
        .enabled,
    isTrue,
  );
}

Iterable<String> _titles(WidgetTester tester) => tester
    .widgetList<NoteListItem>(find.byType(NoteListItem))
    .map((item) => item.note.title);

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;
