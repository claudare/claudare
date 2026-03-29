import 'dart:convert';
import 'dart:typed_data';

// Could use just base64url while removing trailing `==`
abstract interface class IdGenerator {
  static const int byteLength = 16;
  static const int stringLength = 22; // fixed width for 128-bit in Base58

  Uint8List generateBytes();
  String generateId();

  static String bytesToString(Uint8List bytes) {
    if (bytes.length != byteLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Expected exactly $byteLength bytes',
      );
    }

    final encoded = base64UrlEncode(bytes).replaceAll('=', '');
    assert(
      encoded.length == stringLength,
      'Encoded string must be $stringLength chars, got ${encoded.length}',
    );

    return encoded;
  }

  static Uint8List stringToBytes(String value) {
    if (value.length != stringLength) {
      throw FormatException(
        'Invalid length: expected $stringLength, got ${value.length}',
        value,
      );
    }

    // base64 decoder expects proper padding
    final padded = '$value==';

    Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Url.decode(padded));
    } on FormatException {
      throw FormatException('Invalid base64url ID', value);
    }
    assert(
      bytes.length == byteLength,
      'Decoded bytes length invalid: expected $byteLength, got ${bytes.length}',
    );
    // keeping this just in case
    if (bytes.length != byteLength) {
      throw FormatException(
        'Decoded bytes length invalid: expected $byteLength, got ${bytes.length}',
        value,
      );
    }

    return bytes;
  }
}
