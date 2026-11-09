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
  late ProjectionRun projectionRun;

  setUp(() {
    store = MemoryEventStore(eventFetchPageSize: 1);
    fts = _ObservedFts();
    application = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      fts: fts,
    );
    projectionRun = application.startProjections();
    addTearDown(projectionRun.cancel);
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
    expect(await application.query.noteSearch('missing'), isEmpty);
  });

  test('commands index note content in the supplied backend', () async {
    await write('one', 'Notebook');
    await waitForIndex(fts);

    expect(await fts.query('NOTE', 10), ['one']);
  });

  test('search returns resolved note states in relevance order', () async {
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

  test('a fresh index replays existing note history', () async {
    await write('one', 'Existing content');
    await projectionRun.cancel();
    final backend = _ObservedFts();
    final restarted = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      fts: backend,
    );
    final restartedRun = restarted.startProjections();
    addTearDown(restartedRun.cancel);

    await waitForIndex(backend);

    expect(
      (await restarted.query.noteSearch('existing')).map((note) => note.noteId),
      ['one'],
    );
  });

  test('search returns at most twenty notes in relevance order', () async {
    for (var index = 0; index < 21; index++) {
      await write('note-$index', List.filled(index + 1, 'word').join(' '));
    }
    await waitForIndex(fts);

    final results = await application.query.noteSearch('word');

    expect(results.map((note) => note.noteId), [
      for (var index = 20; index > 0; index--) 'note-$index',
    ]);
  });

  test('permanent stream deletion removes a note from search', () async {
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
}

class _ObservedFts extends MemoryFts {
  final _waiters = <int, Completer<void>>{};
  int _revision = -1;

  Future<void> waitForRevision(int revision) => _revision >= revision
      ? Future<void>.value()
      : (_waiters[revision] ??= Completer<void>()).future;

  @override
  Future<void> upsert(String id, String content, int revision) async {
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
