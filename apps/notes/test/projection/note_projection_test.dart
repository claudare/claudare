import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

void main() {
  late NoteProjection projection;
  late NoteModel model;
  var position = 0;
  final time = DateTime.utc(2026);

  void apply(NoteEvent event) => projection.apply(
    model,
    EventEnvelope(
      actor: 'actor',
      streamPath: 'note/one',
      event: event,
      occuredAt: time,
      logPosition: position++,
    ),
  );

  setUp(() {
    projection = const NoteProjection('one');
    model = projection.load().model;
    position = 0;
  });

  test('content edits update the existing document', () {
    apply(const NoteCreated());
    final document = model.contentDocument;
    apply(NoteContentUpdated(change: CrdtTextTestUtils.singleChange('Body')));
    expect(model.content, 'Body');
    expect(model.contentDocument, same(document));
  });

  test('permanent deletion clears the model', () {
    apply(const NoteCreated());
    apply(NoteContentUpdated(change: CrdtTextTestUtils.singleChange('Body')));
    projection.onStreamDeleted(
      model,
      StreamDeletion(
        actor: 'actor',
        streamPath: 'note/one',
        occuredAt: time,
        logPosition: position,
      ),
    );
    expect(model.exists, isFalse);
    expect(model.isDeleted, isTrue);
    expect(model.content, isEmpty);
  });
}
