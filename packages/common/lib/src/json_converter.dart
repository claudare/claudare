import 'dart:convert';
import 'dart:typed_data';

// follow this signature for converters
class JsonConverter {
  const JsonConverter();

  static Uint8List encode(Object value) {
    final jsonString = jsonEncode(value);
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  static T decode<T>(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    return jsonDecode(jsonString) as T;
  }
}
