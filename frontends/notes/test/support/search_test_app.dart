import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:crdt/crdt_text.dart';
import 'package:fts/fts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes_app/notes_app.dart';
import 'package:time_provider/time_provider.dart';

class SearchTestApp {
  final MemoryEventStore store;
  final SearchTestFts fts = SearchTestFts();
  late final NotesApp application = NotesApp(
    cqrsRuntime: store is ProjectionLoadingStore
        ? _LoadingRuntime(store as ProjectionLoadingStore)
        : CqrsTestRuntime(eventStore: store),
    fts: fts,
  );
  late final Future<void> projectionsReady = application.startProjections();

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
}

class _LoadingRuntime extends CqrsRuntime {
  final ProjectionLoadingStore store;

  _LoadingRuntime(this.store)
    : super(
        eventStore: store,
        actor: 'test-actor',
        logger: const NoopLogger(),
        idGenerator: IdGeneratorSequential(),
        timeProvider: FakeTimeProviderStatic.zero(),
      );

  @override
  LiveProjection<TModel, TEvent> liveProjection<
    TModel extends Object,
    TEvent extends Object
  >(Projection<TModel, TEvent> projection) => LiveProjection(
    projection,
    logPlayer: _LoadingLogPlayer(store),
    eventRegistry: eventRegistry,
  );
}

class _LoadingLogPlayer extends LogPlayer {
  final ProjectionLoadingStore store;

  _LoadingLogPlayer(this.store) : super(store);

  @override
  Stream<StoredEvent> followLog(
    LogFilter filter, {
    int fromPosition = 0,
    void Function()? caughtUp,
  }) async* {
    if (!store.loadingStarted.isCompleted) store.loadingStarted.complete();
    await store.loading.future;
    yield* super.followLog(
      filter,
      fromPosition: fromPosition,
      caughtUp: caughtUp,
    );
  }
}

Future<void> pumpSearchCompletion(
  WidgetTester tester,
  Future<void> future,
) async {
  var completed = false;
  final completion = future.whenComplete(() => completed = true);
  completion.ignore();
  // Stream cancellation schedules work outside the widget test clock.
  for (var attempt = 0; attempt < 100 && !completed; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 1));
  }
  expect(completed, isTrue, reason: 'Search projection did not finish');
  await completion;
}

Future<void> pumpSearchProjection(
  WidgetTester tester,
  SearchTestApp fixture,
) async {
  fixture.projectionsReady.ignore();
  final store = fixture.store;
  final loading = store is ProjectionLoadingStore
      ? store.loadingStarted.future
      : fixture.application.query.searchReady;
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
