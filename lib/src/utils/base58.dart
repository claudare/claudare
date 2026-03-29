import 'dart:typed_data';

class Base58 {
  Base58._();

  static const String _base58Chars =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  static const int _base58Radix = 58;

  static String intToStringPadded(int number, int length) {
    if (number < 0) {
      throw ArgumentError('Number must be non-negative: got $number');
    }
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'Must be > 0');
    }

    if (number == 0) {
      return '1'.padLeft(length, '1');
    }

    var remaining = number;
    var result = '';
    while (remaining > 0) {
      result = _base58Chars[remaining % _base58Radix] + result;
      remaining = remaining ~/ _base58Radix;
    }

    if (result.length > length) {
      throw StateError('Value exceeds fixed Base58 length of $length');
    }

    return result.padLeft(length, '1');
  }

  static int intFromString(String str) {
    var result = 0;
    for (var i = 0; i < str.length; i++) {
      final char = str[i];
      final value = _base58Chars.indexOf(char);
      if (value == -1) {
        throw FormatException('Invalid Base58 character: $char', str);
      }
      result = result * _base58Radix + value;
    }
    return result;
  }

  /// Generic bytes -> fixed-length Base58.
  /// This looks scary, but it may be needed for lexiographic sorting
  static String uInt8ListToString(
    Uint8List bytes, {
    required int expectedByteLength,
    required int expectedStringLength,
  }) {
    if (bytes.length != expectedByteLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Expected exactly $expectedByteLength bytes',
      );
    }

    var n = BigInt.zero;
    for (final b in bytes) {
      n = (n << 8) | BigInt.from(b);
    }

    final out = _bigIntToBase58Padded(n, expectedStringLength);
    if (out.length != expectedStringLength) {
      throw StateError('Encoded string must be $expectedStringLength chars');
    }
    return out;
  }

  /// Generic fixed-length Base58 -> bytes.
  static Uint8List uInt8ListFromString(
    String value, {
    required int expectedByteLength,
    required int expectedStringLength,
  }) {
    if (value.length != expectedStringLength) {
      throw FormatException(
        'Invalid length: expected $expectedStringLength, got ${value.length}',
        value,
      );
    }

    final n = _base58ToBigInt(value);
    final max = (BigInt.one << (expectedByteLength * 8)) - BigInt.one;
    if (n < BigInt.zero || n > max) {
      throw FormatException(
        'Base58 value out of $expectedByteLength-byte range',
        value,
      );
    }

    final out = Uint8List(expectedByteLength);
    var temp = n;
    for (var i = expectedByteLength - 1; i >= 0; i--) {
      out[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }

    if (out.length != expectedByteLength) {
      throw StateError('Decoded bytes must be $expectedByteLength bytes');
    }

    return out;
  }

  static String _bigIntToBase58Padded(BigInt number, int length) {
    if (number < BigInt.zero) {
      throw ArgumentError('Number must be non-negative: got $number');
    }
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'Must be > 0');
    }

    if (number == BigInt.zero) {
      return '1'.padLeft(length, '1');
    }

    final bigRadix = BigInt.from(_base58Radix);
    var n = number;
    var result = '';

    while (n > BigInt.zero) {
      final rem = (n % bigRadix).toInt();
      result = _base58Chars[rem] + result;
      n = n ~/ bigRadix;
    }

    if (result.length > length) {
      throw StateError('Value exceeds fixed Base58 length of $length');
    }

    return result.padLeft(length, '1');
  }

  static BigInt _base58ToBigInt(String str) {
    final bigRadix = BigInt.from(_base58Radix);
    var result = BigInt.zero;

    for (var i = 0; i < str.length; i++) {
      final value = _base58Chars.indexOf(str[i]);
      if (value == -1) {
        throw FormatException('Invalid Base58 character: ${str[i]}', str);
      }
      result = result * bigRadix + BigInt.from(value);
    }

    return result;
  }
}
