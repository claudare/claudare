import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/screens/home/note_search_controller.dart';

import 'support/search_test_app.dart';

void main() {
  testWidgets('debounces changes for 100 ms using the latest query', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    final controller = await _controller(tester, fixture);
    controller.setQuery('n');
    await tester.pump(const Duration(milliseconds: 99));
    expect(fixture.fts.queries, isEmpty);
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 99));
    expect(fixture.fts.queries, isEmpty);
    expect(controller.isLoading, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.fts.queries, ['note']);
    expect(fixture.fts.limits, [20]);
    expect(controller.isLoading, isFalse);
  });

  for (final query in ['', ' ', '\n\t']) {
    testWidgets('blank query ${query.codeUnits} cancels pending search', (
      tester,
    ) async {
      final fixture = SearchTestApp();
      final controller = await _controller(tester, fixture);
      controller.setQuery('note');
      controller.setQuery(query);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.fts.queries, isEmpty);
      expect(controller.hasQuery, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.results, isEmpty);
    });
  }

  testWidgets('clearing removes cached results immediately', (tester) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    final controller = await _controller(tester, fixture);
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.results, hasLength(1));
    controller.setQuery('');
    expect(controller.results, isEmpty);
    expect(controller.hasQuery, isFalse);
    expect(controller.isLoading, isFalse);
  });

  for (final obsoleteError in [false, true]) {
    testWidgets('ignores stale ${obsoleteError ? 'errors' : 'responses'}', (
      tester,
    ) async {
      final fixture = SearchTestApp();
      await fixture.write('one', 'note');
      final controller = await _controller(tester, fixture);
      final old = Completer<List<String>>();
      final latest = Completer<List<String>>();
      fixture.fts.onQuery = (query) =>
          query == 'old' ? old.future : latest.future;
      controller.setQuery('old');
      await tester.pump(const Duration(milliseconds: 100));
      controller.setQuery('latest');
      await tester.pump(const Duration(milliseconds: 100));
      latest.complete(['one']);
      await tester.pump();
      final snapshot = controller.results;
      if (obsoleteError) {
        old.completeError(Exception('Obsolete failure'));
      } else {
        old.complete([]);
      }
      await tester.pump();
      expect(controller.results, same(snapshot));
      expect(controller.results.single.noteId, 'one');
      expect(controller.searchError, isNull);
      expect(controller.isLoading, isFalse);
    });
  }

  testWidgets('clearing ignores an in-flight response', (tester) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    final controller = await _controller(tester, fixture);
    final response = Completer<List<String>>();
    fixture.fts.onQuery = (_) => response.future;
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 100));
    controller.setQuery('');
    response.complete(['one']);
    await tester.pump();
    expect(controller.results, isEmpty);
    expect(controller.isLoading, isFalse);
  });

  testWidgets('a failed search is cleared by changing the query', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    final controller = await _controller(tester, fixture);
    fixture.fts.onQuery = (_) => Future.error(Exception('Search failed'));
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.searchError, isException);
    expect(controller.isLoading, isFalse);
    fixture.fts.onQuery = null;
    controller.setQuery('other');
    expect(controller.searchError, isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.searchError, isNull);
  });

  for (final pendingResponse in [false, true]) {
    testWidgets(
      'disposal cancels ${pendingResponse ? 'delivery' : 'debounce'}',
      (tester) async {
        final fixture = SearchTestApp();
        _stopAfterTest(tester, fixture);
        final controller = NoteSearchController(fixture.application);
        await pumpSearchProjection(tester, fixture);
        var notifications = 0;
        controller.addListener(() => notifications++);
        final response = Completer<List<String>>();
        fixture.fts.onQuery = (_) => response.future;
        controller.setQuery('note');
        if (pendingResponse) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        controller.dispose();
        final before = notifications;
        if (pendingResponse) {
          response.completeError(Exception('Disposed search'));
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(notifications, before);
        expect(fixture.fts.queries, pendingResponse ? ['note'] : isEmpty);
      },
    );
  }

  testWidgets('waits for readiness and searches the latest query', (
    tester,
  ) async {
    final store = ProjectionLoadingStore();
    final fixture = SearchTestApp(store: store);
    final controller = await _controller(tester, fixture);
    controller.setQuery('old');
    expect(controller.isLoading, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isLoading, isTrue);
    controller.setQuery('latest');
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isReady, isFalse);
    expect(fixture.fts.queries, isEmpty);
    store.loading.complete();
    await tester.pump();
    expect(controller.isReady, isTrue);
    expect(fixture.fts.queries, ['latest']);
    expect(controller.isLoading, isFalse);
  });

  testWidgets('readiness completion preserves the pending debounce', (
    tester,
  ) async {
    final store = ProjectionLoadingStore();
    final fixture = SearchTestApp(store: store);
    final controller = await _controller(tester, fixture);
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 50));
    store.loading.complete();
    await tester.pump();
    expect(fixture.fts.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fixture.fts.queries, ['note']);
  });

  testWidgets('disposal ignores pending readiness', (tester) async {
    final store = ProjectionLoadingStore();
    final fixture = SearchTestApp(store: store);
    _stopAfterTest(tester, fixture);
    final controller = NoteSearchController(fixture.application);
    await pumpSearchProjection(tester, fixture);
    controller.setQuery('note');
    controller.dispose();
    store.loading.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fixture.fts.queries, isEmpty);
    expect(controller.isReady, isFalse);
  });

  testWidgets('setting the same query keeps the cached results', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    final controller = await _controller(tester, fixture);
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 100));
    final results = controller.results;
    controller.setQuery('note');
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.results, same(results));
    expect(fixture.fts.queries, ['note']);
  });
}

Future<NoteSearchController> _controller(
  WidgetTester tester,
  SearchTestApp fixture,
) async {
  _stopAfterTest(tester, fixture);
  final controller = NoteSearchController(fixture.application);
  addTearDown(controller.dispose);
  await pumpSearchProjection(tester, fixture);
  return controller;
}

void _stopAfterTest(WidgetTester tester, SearchTestApp fixture) {
  addTearDown(() async {
    final stopping = fixture.application.projectionStop();
    await tester.pump();
    await stopping;
  });
}
