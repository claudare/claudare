import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/aggregate/note.dart';
import 'package:notes/event/note.dart';
import 'package:notes/screens/note/note_controller.dart';

void main() {
  test(
    'note catchup is paginated, scoped, and resumes after its sequence',
    () async {
      final store = MemoryEventStore(eventFetchPageSize: 1);
      final app = NoteApplication(
        cqrsRuntime: CqrsTestRuntime(eventStore: store),
      );
      final id = await app.command.createNote();
      final other = await app.command.createNote();
      await app.command.updateNoteTitle(other, 'Other');
      await app.command.updateNoteTitle(id, 'Title');
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        'Body',
        actorId: 'remote',
      );
      final aggregate = noteAggregate(id)..sequence = 0;
      final events = <EventEnvelope<NoteEvent>>[];
      await app.query.catchupNote(aggregate, onApplied: events.add);
      expect(events.map((event) => event.event.runtimeType), [
        NoteTitleUpdated,
        NoteContentUpdated,
      ]);
      expect(events.every((event) => event.event.noteId == id), isTrue);
      expect(events.first.actor, app.actor);
      expect(aggregate.sequence, 4);
    },
    skip: 'Known bug: noteAggregate filters the literal noteId path.',
  );

  test(
    'refresh advances past non-content events and empty reads',
    () async {
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
    },
    skip: 'Known bug: noteAggregate filters the literal noteId path.',
  );

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
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        'One',
        actorId: 'remote',
      );
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        ' two',
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
    skip: 'Known bug: noteAggregate filters the literal noteId path.',
  );
}

class _ObservedStore extends MemoryEventStore {
  final List<int> reads = [];
  int? failAt;

  _ObservedStore() : super(eventFetchPageSize: 1);

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) {
    reads.add(fromPosition);
    if (failAt == fromPosition) {
      failAt = null;
      return Future.error(Exception('Interrupted event read'));
    }
    return super.getLogEvents(fromPosition);
  }
}
