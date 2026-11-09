import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFts fts;
  late SearchProjection projection;
  var position = 0;
  final time = DateTime.utc(2026);

  setUp(() {
    fts = MemoryFts();
    projection = SearchProjection(fts);
    position = 0;
  });

  Future<void> apply(NoteEvent event, {String noteId = 'one'}) =>
      projection.apply(
        EventEnvelope(
          actor: 'actor',
          streamPath: 'note/$noteId',
          event: event,
          occuredAt: time,
          logPosition: position++,
        ),
      );

  Future<void> write(String noteId, String content) async {
    await apply(const NoteCreated(), noteId: noteId);
    await apply(
      NoteContentUpdated(change: CrdtTextTestUtils.singleChange(content)),
      noteId: noteId,
    );
  }

  Future<void> delete(String noteId) => projection.onStreamDeleted(
    StreamDeletion(
      actor: 'actor',
      streamPath: 'note/$noteId',
      occuredAt: time,
      logPosition: position++,
    ),
  );

  test('starts replay from the beginning', () async {
    expect(await projection.load(), -1);
  });

  test('indexes note content in the supplied backend', () async {
    await write('one', 'Notebook content');

    expect(await fts.query('NOTE', 10), ['one']);
  });

  test('replaces indexed content after CRDT edits', () async {
    final document = CrdtText();
    await apply(const NoteCreated());
    await apply(
      NoteContentUpdated(
        change: CrdtTextTestUtils.applyChangeToDocument(document, 'Old')!,
      ),
    );
    await apply(
      NoteContentUpdated(
        change: CrdtTextTestUtils.applyChangeToDocument(document, 'New')!,
      ),
    );

    expect(await projection.search('old new', resultCount: 10), ['one']);
    expect(await projection.search('old', resultCount: 10), isEmpty);
  });

  test('keeps content from different note streams separate', () async {
    await write('one', 'First');
    await write('two', 'Second');

    expect(await projection.search('fir', resultCount: 10), ['one']);
  });

  test('search preserves backend ranking and result limit', () async {
    await write('one', 'note');
    await write('two', 'note notebook');
    await write('three', 'note notebook notes');

    expect(await projection.search('note', resultCount: 2), ['three', 'two']);
  });

  test('stores the event log position as the index revision', () async {
    await write('one', 'Content');

    expect(await fts.getRevision(), 1);
  });

  test('permanent deletion removes only the deleted search entry', () async {
    await write('one', 'Content');
    await write('two', 'Content');

    await delete('one');

    expect(await projection.search('content', resultCount: 10), ['two']);
  });

  test('permanent deletion removes cached note state', () async {
    await write('one', 'Content');

    await delete('one');

    expect(projection.notes, isEmpty);
  });

  for (final noteId in ['one', 'missing']) {
    test('deleting $noteId stores the deletion log position', () async {
      await write('one', 'Content');

      await delete(noteId);

      expect(await fts.getRevision(), 2);
    });
  }
}
