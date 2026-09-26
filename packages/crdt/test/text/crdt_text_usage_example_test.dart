import 'dart:convert';

import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

void main() {
  test('incremental delivery preserves prepared and later local edits', () {
    // Alice opens an empty document and edits her private draft.
    final aliceDocument = CrdtText();
    final alice = CrdtTextTestUtils.editContext(
      'alice',
      document: aliceDocument,
    );
    updateText(alice, 'Hello');

    // Saving applies Alice's batch to her document and acknowledges it.
    CrdtTextTestUtils.save(alice, document: aliceDocument);

    // Bob forks the saved history, then opens a draft with his own actor ID.
    final bobDocument = aliceDocument.fork();
    final bob = CrdtTextTestUtils.editContext('bob', document: bobDocument);

    // Alice prepares a local edit for saving, without persisting it yet.
    alice.insert(0, 'Local ');
    final prepared = alice.prepareChange()!;

    // A later edit stays outside the already prepared batch.
    alice.insert(0, 'Later ');

    // Bob edits independently and saves before receiving Alice's changes.
    bob.insert(bob.length, ' remote');
    final remote = CrdtTextTestUtils.save(bob, document: bobDocument);

    // Delivery updates Alice's document and draft, preserving her pending edits.
    CrdtTextTestUtils.deliver(remote, document: aliceDocument, context: alice);
    expect(alice.text, 'Later Local Hello remote');
    expect(alice.prepareChange(), same(prepared));

    // Alice's prepared batch is now persisted, excluding her later edit.
    aliceDocument.applyChange(prepared);

    // Its local echo can arrive before the save is acknowledged.
    alice.applyChange(prepared);
    expect(alice.prepareChange(), same(prepared));

    // Bob receives that persisted batch and applies it to his document and draft.
    CrdtTextTestUtils.deliver(prepared, document: bobDocument, context: bob);

    // Acknowledging the successful save leaves Alice's later edit pending.
    alice.acknowledgeChange(prepared);
    expect(alice.hasPendingChanges, isTrue);

    // Alice saves the remaining edit as a separate batch.
    final later = CrdtTextTestUtils.save(alice, document: aliceDocument);

    // Bob receives the final batch after the earlier batch it depends on.
    CrdtTextTestUtils.deliver(later, document: bobDocument, context: bob);

    // Both documents and drafts converge, and neither writer has pending edits.
    expect(alice.prepareChange(), isNull);
    expect(bob.prepareChange(), isNull);
    expect(aliceDocument.toJson(), bobDocument.toJson());
    expect(aliceDocument.text, 'Later Local Hello remote');
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
