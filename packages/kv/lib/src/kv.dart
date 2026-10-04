/// Stores string values by key.
abstract interface class Kv {
  /// Returns the value, or null when [key] is absent.
  Future<String?> getString(String key);

  /// Sets the value, replacing any existing value.
  Future<void> setString(String key, String value);

  /// Sets all values atomically.
  Future<void> setAllStrings(Map<String, String> values);

  /// Deletes [key], doing nothing when it is absent.
  Future<void> delete(String key);

  /// Lists keys matching the literal [prefix], ordered by key.
  Future<List<String>> listKeys(String prefix);
}

/// Converts string and boolean values for [Kv] storage.
extension KvConversions on Kv {
  /// Returns a boolean, or null when [key] is absent.
  Future<bool?> getBool(String key) => getTyped<bool>(key);

  /// Stores [value] as `true` or `false`.
  Future<void> setBool(String key, bool value) => setTyped<bool>(key, value);

  /// Returns a string or boolean, or null when [key] is absent.
  Future<T?> getTyped<T>(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    if (T == String) return value as T;
    if (T == bool) {
      return switch (value) {
        'true' => true as T,
        'false' => false as T,
        _ => throw StateError('Invalid boolean value: $value'),
      };
    }
    throw UnsupportedError('Unsupported type: $T');
  }

  /// Stores a string or boolean value.
  Future<void> setTyped<T>(String key, T value) async {
    await setString(key, _toString(value));
  }

  /// Converts all string and boolean values before writing them atomically.
  Future<void> setAll(Map<String, dynamic> values) async {
    final strings = <String, String>{
      for (final entry in values.entries) entry.key: _toString(entry.value),
    };
    await setAllStrings(strings);
  }

  static String _toString(Object? value) => switch (value) {
    String value => value,
    bool value => value ? 'true' : 'false',
    _ => throw UnsupportedError('Unsupported type: ${value.runtimeType}'),
  };
}
