import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:crdt/crdt_text.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:test/test.dart';

void main() {
  late MemoryEventStore store;
  late _ObservedFts fts;
  late NotesApp application;
  Object? projectionFailure;

  setUp(() {
    store = MemoryEventStore(eventFetchPageSize: 1);
    fts = _ObservedFts();
    projectionFailure = null;
    application = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      fts: fts,
    );
    addTearDown(() async {
      final failure = projectionFailure;
      if (failure == null) {
        await application.stopProjections();
      } else {
        await expectLater(
          application.stopProjections(),
          throwsA(same(failure)),
        );
      }
    });
  });

  Future<void> write(String noteId, String content) async {
    await application.command.createNote(noteId);
    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.singleChange(content),
    );
  }

  Future<void> waitForIndex(_ObservedFts backend) async {
    final position = await store.getLogPosition(const LogFilter.all());
    await backend.waitForRevision(position);
  }

  test('search returns no matches for an empty index', () async {
    await application.startProjections();
    expect(await application.query.noteSearch('missing'), isEmpty);
  });

  test('commands index note content in the supplied backend', () async {
    await application.startProjections();
    await write('one', 'Notebook');
    await waitForIndex(fts);

    expect(await fts.query('NOTE', 10), ['one']);
  });

  test('search returns resolved note states in relevance order', () async {
    await application.startProjections();
    await write('one', 'note');
    await write('two', 'note notebook');
    await application.command.updateNoteTitle('two', 'Title');
    await waitForIndex(fts);

    final results = await application.query.noteSearch('NOTE');

    expect(results.map((note) => note.noteId), ['two', 'one']);
    expect(results.first.title, 'Title');
    expect(results.first.content, 'note notebook');
    expect(results.first.exists, isTrue);
  });

  test(
    'search follows content edits after the projection catches up',
    () async {
      await application.startProjections();
      final document = CrdtText();
      await application.command.createNote('one');
      await application.command.updateNoteContent(
        'one',
        CrdtTextTestUtils.applyChangeToDocument(document, 'Old')!,
      );
      await waitForIndex(fts);

      await application.command.updateNoteContent(
        'one',
        CrdtTextTestUtils.applyChangeToDocument(document, 'New')!,
      );
      await waitForIndex(fts);

      expect(await application.query.noteSearch('old'), isEmpty);
      expect(
        (await application.query.noteSearch('new')).map((note) => note.noteId),
        ['one'],
      );
    },
  );

  test('permanent stream deletion removes a note from search', () async {
    await application.startProjections();
    await write('one', 'Content');
    await waitForIndex(fts);
    final time = DateTime.utc(2026);
    final accepted = await store.addStoredCommand(
      StoredCommand(
        commandId: const CommandId('deleting-actor', 1),
        dependency: (await store.getState()).logVersion,
        occuredAt: time,
        events: [
          StoredCommandEvent(
            streamPath: 'note/one',
            encodedEvent: EncodedEvent.streamDeleted(),
            occuredAt: time,
          ),
        ],
      ),
    );
    expect(accepted, isTrue);
    await waitForIndex(fts);

    expect(await application.query.noteSearch('content'), isEmpty);
  });

  test('starting completes after existing notes are searchable', () async {
    await write('one', 'Existing content');
    final indexing = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    fts.beforeUpsert = () {
      if (!indexing.isCompleted) indexing.complete();
      return release.future;
    };
    var ready = false;
    final starting = application.startProjections().then((_) => ready = true);
    await indexing.future;
    expect(ready, isFalse);

    release.complete();
    await starting;

    expect(await fts.query('existing', 20), ['one']);
  });

  test('search waits for initial indexing', () async {
    await write('one', 'Existing content');
    final indexing = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    fts.beforeUpsert = () {
      if (!indexing.isCompleted) indexing.complete();
      return release.future;
    };
    final starting = application.startProjections();
    var searched = false;
    final search = application.query.noteSearch('existing').then((results) {
      searched = true;
      return results;
    });
    await indexing.future;
    expect(searched, isFalse);

    release.complete();
    await starting;

    expect((await search).single.noteId, 'one');
  });

  test('projectionsDone completes after stopping', () async {
    await application.startProjections();
    var finished = false;
    final done = application.projectionsDone.then((_) => finished = true);
    await application.query.noteSearch('missing');
    expect(finished, isFalse);

    await application.stopProjections();
    await done;

    expect(finished, isTrue);
  });

  test('initial indexing failures fail startup and search', () async {
    await write('one', 'Content');
    final error = Exception('Index unavailable');
    projectionFailure = error;
    fts.beforeUpsert = () => throw error;

    await expectLater(application.startProjections(), throwsA(same(error)));
    await expectLater(
      application.query.noteSearch('content'),
      throwsA(same(error)),
    );
    await expectLater(application.projectionsDone, throwsA(same(error)));
  });

  test(
    'later indexing failures are reported through projectionsDone',
    () async {
      await application.startProjections();
      final error = Exception('Index unavailable');
      projectionFailure = error;
      fts.beforeUpsert = () => throw error;
      final done = expectLater(
        application.projectionsDone,
        throwsA(same(error)),
      );

      await write('one', 'Content');
      await done;

      await application.query.searchReady;
    },
  );
}

class _ObservedFts extends MemoryFts {
  final _waiters = <int, Completer<void>>{};
  int _revision = -1;
  Future<void> Function()? beforeUpsert;

  Future<void> waitForRevision(int revision) => _revision >= revision
      ? Future<void>.value()
      : (_waiters[revision] ??= Completer<void>()).future;

  @override
  Future<void> upsert(String id, String content, int revision) async {
    await beforeUpsert?.call();
    await super.upsert(id, content, revision);
    _applied(revision);
  }

  @override
  Future<void> delete(String id, int revision) async {
    await super.delete(id, revision);
    _applied(revision);
  }

  void _applied(int revision) {
    _revision = revision;
    for (final target in _waiters.keys.toList()) {
      if (target <= revision) _waiters.remove(target)!.complete();
    }
  }
}
