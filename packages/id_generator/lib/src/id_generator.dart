import 'dart:convert';
import 'dart:typed_data';

abstract interface class IdGenerator {
  static const int byteLength = 16;
  static const int stringLength = 22;

  Uint8List generateBytes();
  String generateId();

  static String bytesToString(Uint8List bytes) {
    if (bytes.length != byteLength) {
      throw FormatException(
        'Invalid byte length: expected $byteLength, got ${bytes.length}',
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
    if (bytes.length != byteLength) {
      throw FormatException(
        'Decoded bytes length invalid: expected $byteLength, got ${bytes.length}',
        value,
      );
    }

    return bytes;
  }
}
