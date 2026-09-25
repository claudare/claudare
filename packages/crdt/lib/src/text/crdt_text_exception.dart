part of 'crdt_text.dart';

/// An incoming change violates the document's causal or identity invariants.
final class CrdtTextException implements Exception {
  final String message;

  const CrdtTextException(this.message);

  @override
  String toString() => 'CrdtTextException: $message';
}
