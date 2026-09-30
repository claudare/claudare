/// A string key and its stored value.
class KeyValue {
  final String key;
  final String value;

  const KeyValue({required this.key, required this.value});
}

/// Stores string values by key.
abstract interface class Kv {
  /// Returns the value, or null when [key] is absent.
  Future<String?> get(String key);

  /// Sets the value. Overrides if already exists.
  Future<void> set(String key, String value);

  /// Sets all values atomically. Later entries override earlier duplicates.
  Future<void> setAll(List<KeyValue> values);

  /// Deletes [key], doing nothing when it is absent.
  Future<void> delete(String key);

  /// Lists entries whose keys start with the literal [prefix], ordered by key.
  Future<List<KeyValue>> list(String prefix);
}
