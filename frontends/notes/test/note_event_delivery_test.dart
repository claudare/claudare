import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/note/note_controller.dart';

import 'support/queries.dart';

void main() {
  late _ObservedStore store;
  late NotesApp app;
  late NoteController controller;
  setUp(() async {
    store = _ObservedStore();
    app = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      fts: NoopFts(),
      logger: const NoopLogger(),
    );
    await app.command.createNote('one');
    controller = NoteController(app, noteId: 'one');
    await controller.load();
    addTearDown(controller.dispose);
  });

  test(
    'live updates merge remote content into an unsaved local draft',
    () async {
      final document = controller.content.document;
      controller.content.insert(0, 'Local ');
      final delivered = Completer<void>();
      controller.addListener(() {
        if (document.text == 'Remote' && !delivered.isCompleted) {
          delivered.complete();
        }
      });
      await app.command.testSimulateExternalNoteContentAppend(
        'one',
        'Remote',
        actorId: 'remote',
      );
      await delivered.future;
      expect(controller.content.document, same(document));
      expect(controller.content.text, contains('Local '));
      expect(controller.content.text, contains('Remote'));
      expect(controller.content.hasPendingChanges, isTrue);
    },
  );

  test('replay failure exposes an error and blocks further saves', () async {
    controller.content.insert(0, 'Body');
    store.failReadAfterWrite = true;
    await expectLater(controller.flushChanges(), throwsException);
    final writes = store.writes;
    await expectLater(controller.flushChanges(), throwsException);
    expect(store.writes, writes);
    expect(controller.error, isNotNull);
    expect(controller.content.hasPendingChanges, isTrue);
    expect((await readNote(app, 'one')).content, 'Body');
  });

  test('disposing an editor stops subsequent notifications', () async {
    final other = NoteController(app, noteId: 'one');
    await other.load();
    var notifications = 0;
    other.addListener(() => notifications++);
    other.dispose();
    await app.command.updateNoteTitle('one', 'Remote');
    await controller.refresh();
    expect(notifications, 0);
  });
}

class _ObservedStore extends MemoryEventStore {
  int writes = 0;
  bool failReadAfterWrite = false;
  bool _failNextRead = false;

  _ObservedStore() : super(eventFetchPageSize: 1);

  @override
  Future<void> saveChanges(changes) async {
    await super.saveChanges(changes);
    writes++;
    if (failReadAfterWrite) {
      failReadAfterWrite = false;
      _failNextRead = true;
    }
  }

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  ) {
    if (_failNextRead) {
      _failNextRead = false;
      return Future.error(Exception('Interrupted event read'));
    }
    return super.getLogEvents(filter, fromPosition);
  }
}
