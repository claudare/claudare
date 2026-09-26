import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/event/note.dart';
import 'package:notes/screens/note/note_controller.dart';

void main() {
  test(
    'note events are paginated, scoped, and start at an inclusive version',
    () async {
      final store = MemoryEventStore(eventFetchPageSize: 1);
      final app = NoteApplication(
        cqrsRuntime: CqrsTestRuntime(eventStore: store),
      );
      final id = await app.command.createNote();
      final other = await app.command.createNote();
      await app.command.updateNoteTitle(other, 'Other');
      await app.command.updateNoteTitle(id, 'Title');
      await app.command.simulateExternalNoteContentEdit(
        id,
        'Body',
        actorId: 'remote',
      );
      final events = await app.query.noteEvents(id, fromVersion: 1).toList();
      expect(events.map((event) => event.version), [1, 2]);
      expect(events.first.envelope.event, isA<NoteTitleUpdated>());
      expect(events.last.envelope.event, isA<NoteContentUpdated>());
      expect(
        events.every((event) => event.envelope.event.noteId == id),
        isTrue,
      );
      expect(events.first.envelope.actor, app.actor);
    },
  );

  test('refresh advances past non-content events and empty reads', () async {
    final store = _ObservedStore();
    final app = NoteApplication(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
    );
    final id = await app.command.createNote();
    final controller = NoteController(app);
    addTearDown(controller.dispose);
    await controller.load(id);
    await app.command.updateNoteTitle(id, 'Title');
    await app.command.trashNote(id);
    store.reads.clear();
    await controller.refresh();
    expect(store.reads.first, 1);
    expect(controller.isTrashed, isTrue);
    store.reads.clear();
    await controller.refresh();
    await controller.refresh();
    expect(store.reads, [3, 3]);
    expect(controller.content.prepareChange(), isNull);
  });

  test(
    'refresh resumes after the last successfully delivered event on failure',
    () async {
      final store = _ObservedStore();
      final app = NoteApplication(
        cqrsRuntime: CqrsTestRuntime(eventStore: store),
      );
      final id = await app.command.createNote();
      final controller = NoteController(app);
      addTearDown(controller.dispose);
      await controller.load(id);
      await app.command.simulateExternalNoteContentEdit(
        id,
        'One',
        actorId: 'remote',
      );
      await app.command.simulateExternalNoteContentEdit(
        id,
        'One two',
        actorId: 'remote',
      );
      store.failAt = 2;
      await expectLater(controller.refresh(), throwsException);
      expect(controller.content.text, 'One');
      store.reads.clear();
      await controller.refresh();
      expect(store.reads.first, 2);
      expect(controller.content.text, 'One two');
      expect(controller.content.prepareChange(), isNull);
    },
  );
}

class _ObservedStore extends MemoryEventStore {
  final List<int> reads = [];
  int? failAt;

  _ObservedStore() : super(eventFetchPageSize: 1);

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
  ) {
    reads.add(fromVersion);
    if (failAt == fromVersion) {
      failAt = null;
      return Future.error(Exception('Interrupted event read'));
    }
    return super.getStreamEvents(streamPath, fromVersion);
  }
}
