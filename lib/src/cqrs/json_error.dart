import 'dart:convert';

final class JsonError {
  const JsonError._();

  /// Strict JSON parser/encoder errors.
  static bool isJsonError(Object error) {
    return error is JsonUnsupportedObjectError || error is FormatException;
  }

  /// Broader "JSON pipeline" errors (decode + mapping/use).
  static bool isJsonLikeError(Object error) {
    return isJsonError(error) ||
        error is TypeError ||
        error is NoSuchMethodError;
    // || error is RangeError;
  }
}
