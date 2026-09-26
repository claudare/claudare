part of 'crdt_text.dart';

/// Helpers for creating text fixtures and explicitly delivering test changes.
abstract final class CrdtTextTestUtils {
  /// Opens an independent draft of [document], or an empty document.
  static CrdtTextEditContext editContext(
    String actorId, {
    CrdtText? document,
  }) => CrdtTextEditContext(document: document ?? CrdtText(), actorId: actorId);

  /// Creates an initial change for nonempty [value].
  static CrdtTextChange singleChange(String value, {String actorId = 'a'}) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Must be nonempty');
    }
    return applyChangeToDocument(CrdtText(), value, actorId: actorId)!;
  }

  /// Updates [document] and returns its change, or null for unchanged text.
  static CrdtTextChange? applyChangeToDocument(
    CrdtText document,
    String value, {
    String actorId = 'a',
  }) {
    final context = editContext(actorId, document: document);
    updateText(context, value);
    if (!context.hasPendingChanges) return null;
    return save(context, document: document);
  }

  /// Simulates a successful save of the prepared batch and acknowledges it.
  ///
  /// Applies the batch to [document] first when supplied. Without a document,
  /// persistence is assumed. Throws [StateError] when there are no pending edits.
  static CrdtTextChange save(
    CrdtTextEditContext context, {
    CrdtText? document,
  }) {
    final change = context.prepareChange();
    if (change == null) throw StateError('There are no pending text edits');
    document?.applyChange(change);
    context.acknowledgeChange(change);
    return change;
  }

  /// Delivers [change] to persisted state and its draft without acknowledgment.
  static void deliver(
    CrdtTextChange change, {
    required CrdtText document,
    required CrdtTextEditContext context,
  }) {
    document.applyChange(change);
    context.applyChange(change);
  }
}
