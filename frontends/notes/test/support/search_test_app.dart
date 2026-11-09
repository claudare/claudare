import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:crdt/crdt_text.dart';
import 'package:fts/fts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_app.dart';

class SearchTestApp {
  final MemoryEventStore store;
  final SearchTestFts fts = SearchTestFts();
  late final NotesApp application = NotesApp(
    cqrsRuntime: CqrsTestRuntime(eventStore: store),
    fts: fts,
  );
  late final ProjectionRun projectionRun = application.startProjections();

  SearchTestApp({MemoryEventStore? store})
    : store = store ?? MemoryEventStore();

  Future<void> write(
    String id,
    String content, {
    String? title,
    bool trashed = false,
  }) async {
    await application.command.createNote(id);
    await application.command.updateNoteTitle(id, title ?? id);
    await application.command.updateNoteContent(
      id,
      CrdtTextTestUtils.singleChange(content),
    );
    if (trashed) await application.command.trashNote(id);
  }
}

class SearchTestFts extends MemoryFts {
  final queries = <String>[];
  final limits = <int>[];
  Future<List<String>> Function(String)? onQuery;

  @override
  Future<List<String>> query(String query, int resultCount) {
    queries.add(query);
    limits.add(resultCount);
    return onQuery?.call(query) ?? super.query(query, resultCount);
  }
}

class ProjectionLoadingStore extends MemoryEventStore {
  final loading = Completer<void>();
  final loadingStarted = Completer<void>();

  @override
  Future<int> getLogPosition(LogFilter filter) async {
    if (!loadingStarted.isCompleted) loadingStarted.complete();
    await loading.future;
    return super.getLogPosition(filter);
  }
}

Future<void> pumpSearchProjection(
  WidgetTester tester,
  SearchTestApp fixture,
) async {
  final projectionRun = fixture.projectionRun;
  final store = fixture.store;
  final loading = store is ProjectionLoadingStore
      ? store.loadingStarted.future
      : projectionRun.ready;
  var completed = false;
  final completion = loading.then((_) => completed = true);
  for (var attempt = 0; attempt < 100 && !completed; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    completed,
    isTrue,
    reason: 'Search projection did not finish starting',
  );
  await completion;
}
