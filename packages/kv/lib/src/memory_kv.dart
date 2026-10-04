import 'package:kv/src/kv.dart';

/// Stores string values in memory for the lifetime of this instance.
class MemoryKv implements Kv {
  final _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setAllStrings(Map<String, String> values) async {
    _values.addAll(values);
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<List<String>> listKeys(String prefix) async =>
      _values.keys.where((key) => key.startsWith(prefix)).toList()..sort();
}
