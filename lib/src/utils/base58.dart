class Base58 {
  // Constants for Base58 encoding
  static const String _base58Chars =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  static const int _base58Radix = 58;

  /// Converts a number to a Base58 string with fixed length
  static String toStringPadded(int number, int length) {
    if (number < 0) {
      throw ArgumentError('Number must be non-negative');
    }

    // Handle zero case
    if (number == 0) {
      return '1'.padLeft(length, '1'); // '1' is the zero character in Base58
    }

    // Convert to Base58
    String result = '';
    int remaining = number;

    while (remaining > 0) {
      result = _base58Chars[remaining % _base58Radix] + result;
      remaining = remaining ~/ _base58Radix;
    }

    // Pad with leading '1' (the zero character in Base58) to ensure fixed length
    return result.padLeft(length, '1');
  }

  /// Parses a Base58 string to an integer
  static int fromString(String str) {
    int result = 0;

    for (int i = 0; i < str.length; i++) {
      final char = str[i];
      final value = _base58Chars.indexOf(char);
      if (value == -1) {
        throw FormatException('Invalid Base58 character: $char', str);
      }
      result = result * _base58Radix + value;
    }

    return result;
  }
}
