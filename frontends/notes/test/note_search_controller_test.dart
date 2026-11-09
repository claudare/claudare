import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/screens/home/note_search_controller.dart';

import 'support/search_test_app.dart';

void main() {
  testWidgets(
    'starts immediately and coalesces changes into the latest query',
    (tester) async {
      final fixture = SearchTestApp();
      final controller = await _controller(tester, fixture);
      controller.setQuery('n');
      expect(fixture.fts.queries, ['n']);
      controller.setQuery('no');
      controller.setQuery('note');
      expect(fixture.fts.queries, ['n']);
      expect(controller.isLoading, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.fts.queries, ['n', 'note']);
      expect(fixture.fts.limits, [20, 20]);
      expect(controller.isLoading, isFalse);
    },
  );

  for (final query in ['', ' ', '\n\t']) {
    testWidgets('blank query ${query.codeUnits} skips queued search', (
      tester,
    ) async {
      final fixture = SearchTestApp();
      final controller = await _controller(tester, fixture);
      controller.setQuery('first');
      await tester.pump();
      controller.setQuery('note');
      controller.setQuery(query);
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.fts.queries, ['first']);
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
    await tester.pump();
    expect(controller.results, hasLength(1));
    controller.setQuery('');
    expect(controller.results, isEmpty);
    expect(controller.hasQuery, isFalse);
    expect(controller.isLoading, isFalse);
    await tester.pump(const Duration(seconds: 1));
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
      controller.setQuery('latest');
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.fts.queries, ['old']);
      if (obsoleteError) {
        old.completeError(Exception('Obsolete failure'));
      } else {
        old.complete(['one']);
      }
      await tester.pump();
      expect(fixture.fts.queries, ['old', 'latest']);
      expect(controller.results, isEmpty);
      expect(controller.searchError, isNull);
      expect(controller.isLoading, isTrue);
      latest.complete(['one']);
      await tester.pump();
      expect(controller.results.single.noteId, 'one');
      expect(controller.searchError, isNull);
      expect(controller.isLoading, isFalse);
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('clearing ignores an in-flight response', (tester) async {
    final fixture = SearchTestApp();
    await fixture.write('one', 'note');
    final controller = await _controller(tester, fixture);
    final response = Completer<List<String>>();
    fixture.fts.onQuery = (_) => response.future;
    controller.setQuery('note');
    await tester.pump();
    controller.setQuery('');
    response.complete(['one']);
    await tester.pump();
    expect(controller.results, isEmpty);
    expect(controller.isLoading, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('clearing ignores an in-flight error', (tester) async {
    final fixture = SearchTestApp();
    final controller = await _controller(tester, fixture);
    final response = Completer<List<String>>();
    fixture.fts.onQuery = (_) => response.future;
    controller.setQuery('note');
    await tester.pump();
    controller.setQuery('');
    response.completeError(Exception('Obsolete search'));
    await tester.pump();
    expect(controller.searchError, isNull);
    expect(controller.isLoading, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a failed search is cleared by changing the query', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    final controller = await _controller(tester, fixture);
    fixture.fts.onQuery = (_) => Future.error(Exception('Search failed'));
    controller.setQuery('note');
    await tester.pump();
    expect(controller.searchError, isException);
    expect(controller.isLoading, isFalse);
    fixture.fts.onQuery = null;
    controller.setQuery('other');
    expect(controller.searchError, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.searchError, isNull);
  });

  testWidgets('disposal skips searches queued during the throttle interval', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    _stopAfterTest(tester, fixture);
    final controller = NoteSearchController(fixture.application);
    await pumpSearchProjection(tester, fixture);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.setQuery('note');
    await tester.pump();
    controller.setQuery('queued');
    controller.dispose();
    final before = notifications;
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, before);
    expect(fixture.fts.queries, ['note']);
  });

  testWidgets('disposal ignores in-flight errors and skips queued searches', (
    tester,
  ) async {
    final fixture = SearchTestApp();
    _stopAfterTest(tester, fixture);
    final controller = NoteSearchController(fixture.application);
    await pumpSearchProjection(tester, fixture);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final response = Completer<List<String>>();
    fixture.fts.onQuery = (_) => response.future;
    controller.setQuery('note');
    await tester.pump();
    controller.setQuery('queued');
    controller.dispose();
    final before = notifications;
    response.completeError(Exception('Disposed search'));
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, before);
    expect(fixture.fts.queries, ['note']);
  });

  testWidgets('waits for readiness and searches the latest query', (
    tester,
  ) async {
    final store = ProjectionLoadingStore();
    final fixture = SearchTestApp(store: store);
    final controller = await _controller(tester, fixture);
    controller.setQuery('old');
    expect(controller.isLoading, isTrue);
    controller.setQuery('latest');
    expect(controller.isReady, isFalse);
    expect(fixture.fts.queries, isEmpty);
    store.loading.complete();
    await tester.pump();
    expect(controller.isReady, isTrue);
    expect(fixture.fts.queries, ['latest']);
    expect(controller.isLoading, isFalse);
    await tester.pump(const Duration(seconds: 1));
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
    await tester.pump(const Duration(seconds: 1));
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
    await tester.pump();
    final results = controller.results;
    controller.setQuery('note');
    await tester.pump(const Duration(seconds: 1));
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
