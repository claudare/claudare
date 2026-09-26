part of 'crdt_text.dart';

/// Helpers for creating text fixtures and explicitly delivering test changes.
abstract final class CrdtTextTestUtils {
  /// Opens an editing context attached to [document], or an empty document.
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
    try {
      updateText(context, value);
      if (!context.hasPendingChanges) return null;
      return save(context);
    } finally {
      context.dispose();
    }
  }

  /// Simulates persistence and replay into the context's source document.
  /// Throws [StateError] when there are no pending edits.
  static CrdtTextChange save(CrdtTextEditContext context) {
    final change = context.prepareChange();
    if (change == null) throw StateError('There are no pending text edits');
    context.document.applyChange(change);
    return change;
  }
}
