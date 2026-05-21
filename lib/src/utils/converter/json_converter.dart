import 'dart:convert';
import 'dart:typed_data';

import 'decode_exception.dart';
import 'encode_exception.dart';

// follow this signature for converters
class JsonConverter {
  const JsonConverter();

  static Uint8List encode<T>(T value) {
    try {
      final jsonString = jsonEncode(value);
      return Uint8List.fromList(utf8.encode(jsonString));
    } on Exception catch (e) {
      throw EncodeException('Failed to encode JSON: $e', error: e);
    } catch (e, st) {
      if (_isJsonLikeError(e)) {
        throw EncodeException('Failed to encode JSON: $e');
      }

      Error.throwWithStackTrace(e, st);
    }
  }

  static T decode<T>(Uint8List bytes) {
    try {
      final jsonString = utf8.decode(bytes);
      return jsonDecode(jsonString) as T;
    } on Exception catch (e) {
      throw DecodeException('Failed to decode JSON: $e', error: e);
    } catch (e, st) {
      if (_isJsonLikeError(e)) {
        throw DecodeException('Failed to decode JSON: $e');
      }

      Error.throwWithStackTrace(e, st);
    }
  }
}

// converts errors to exceptions
bool _isJsonLikeError(Object error) {
  return error is JsonUnsupportedObjectError ||
      error is TypeError ||
      error is NoSuchMethodError;
  // || error is RangeError;
}
