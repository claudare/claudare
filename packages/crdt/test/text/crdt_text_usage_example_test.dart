import 'dart:convert';

import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

void main() {
  test('incremental delivery preserves prepared and later local edits', () {
    final aliceDocument = CrdtText();

    // Alice writes to an empty document and saves the changes
    final alice = CrdtTextEditContext(
      document: aliceDocument,
      actorId: 'alice',
    );
    updateText(alice, 'Hello');
    final initial = alice.prepareChange()!;
    aliceDocument.applyChange(initial);
    alice.acknowledgeChange(initial);

    // Bob inserts the value at the start.
    final bobDocument = CrdtText.fromJson(aliceDocument.toJson());
    final bob = CrdtTextEditContext(document: bobDocument, actorId: 'bob');
    alice.insert(0, 'Local ');
    final prepared = alice.prepareChange()!;
    alice.insert(0, 'Later ');

    // Bob creates a concurrent edit while Alice has a prepared batch.
    bob.insert(bob.length, ' remote');
    final remote = bob.prepareChange()!;
    bobDocument.applyChange(remote);
    bob.acknowledgeChange(remote);
    aliceDocument.applyChange(remote);
    alice.applyChange(remote);
    expect(alice.text, 'Later Local Hello remote');
    expect(alice.prepareChange(), same(prepared));

    // Event delivery can precede acknowledgment of the successful write.
    aliceDocument.applyChange(prepared);
    alice.applyChange(prepared);
    bobDocument.applyChange(prepared);
    bob.applyChange(prepared);
    expect(alice.prepareChange(), same(prepared));
    alice.acknowledgeChange(prepared);
    expect(alice.hasPendingChanges, isTrue);

    final later = alice.prepareChange()!;
    aliceDocument.applyChange(later);
    alice.applyChange(later);
    bobDocument.applyChange(later);
    bob.applyChange(later);
    alice.acknowledgeChange(later);
    expect(alice.prepareChange(), isNull);
    expect(bob.prepareChange(), isNull);
    expect(aliceDocument.toJson(), bobDocument.toJson());
    expect(alice.text, aliceDocument.text);
    expect(bob.text, aliceDocument.text);
  });

  test(
    'edit, persist, replay, acknowledge, and restore document state',
    () async {
      // Aggregate initialization and snapshots require no local actor identity.
      final state = CrdtText();
      final editor = CrdtTextEditContext(document: state, actorId: 'alice');
      final eventLog = <String>[];

      // The application supplies its storage operation.
      Future<void> persist(CrdtTextChange change) async {
        eventLog.add(jsonEncode(change.toJson()));
      }

      updateText(editor, 'Hello');
      final prepared = editor.prepareChange()!;
      editor.insert(editor.length, '!');
      expect(state.text, '');

      await persist(prepared);
      final persisted = CrdtTextChange.fromJson(jsonDecode(eventLog.single));
      state.applyChange(persisted);
      editor.applyChange(persisted); // Event delivery can echo local changes.
      editor.acknowledgeChange(prepared);

      // Edits made while saving stay in the draft and out of the snapshot.
      final snapshot = jsonEncode(state.toJson());
      final restored = CrdtText.fromJson(jsonDecode(snapshot));
      expect(restored.text, 'Hello');
      expect(editor.text, 'Hello!');
      expect(editor.hasPendingChanges, isTrue);

      final later = editor.prepareChange()!;
      await persist(later);
      state.applyChange(CrdtTextChange.fromJson(jsonDecode(eventLog.last)));
      editor.acknowledgeChange(later);

      // A restored snapshot can replay subsequent events without an actor.
      restored.applyChange(CrdtTextChange.fromJson(jsonDecode(eventLog.last)));
      expect(restored.toJson(), state.toJson());
      expect(restored.text, 'Hello!');
      expect(editor.hasPendingChanges, isFalse);

      // Any writer can open the saved state with a fresh, transient context.
      final nextEditor = CrdtTextEditContext(
        document: restored,
        actorId: 'bob',
      );
      expect(nextEditor.prepareChange(), isNull);
      updateText(nextEditor, 'Hello!?');
      expect(nextEditor.prepareChange()!.actorId, 'bob');
      expect(restored.text, 'Hello!');
    },
  );
}
