import 'dart:convert';

import 'package:crdt/crdt_text.dart';
import 'package:test/test.dart';

void main() {
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

      editor.insert(0, 'Hello');
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
      nextEditor.insert(nextEditor.length, '?');
      expect(nextEditor.prepareChange()!.actorId, 'bob');
      expect(restored.text, 'Hello!');
    },
  );
}
