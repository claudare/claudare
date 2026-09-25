import 'dart:typed_data';

const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Decodes a Bitcoin-alphabet Base58 string into bytes.
///
/// Leading `1` characters are preserved as zero bytes. Invalid characters
/// throw a [FormatException].
Uint8List base58Decode(String source) {
  if (source.isEmpty) return Uint8List(0);

  var value = BigInt.zero;
  for (var i = 0; i < source.length; i++) {
    final digit = _alphabet.indexOf(source[i]);
    if (digit < 0) {
      throw FormatException('Invalid Base58 character', source, i);
    }
    value = value * BigInt.from(58) + BigInt.from(digit);
  }

  final decoded = <int>[];
  while (value > BigInt.zero) {
    decoded.add((value & BigInt.from(255)).toInt());
    value >>= 8;
  }

  var leadingZeros = 0;
  while (leadingZeros < source.length && source[leadingZeros] == '1') {
    leadingZeros++;
  }

  return Uint8List.fromList([
    ...List<int>.filled(leadingZeros, 0),
    ...decoded.reversed,
  ]);
}

/// Encodes bytes using the Bitcoin Base58 alphabet.
///
/// Leading zero bytes are represented by leading `1` characters. Values
/// outside the byte range throw an [ArgumentError].
String base58Encode(List<int> bytes) {
  if (bytes.isEmpty) return '';

  var value = BigInt.zero;
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(byte, 'bytes[$i]', 'Must be between 0 and 255');
    }
    value = (value << 8) | BigInt.from(byte);
  }

  final encoded = <String>[];
  final radix = BigInt.from(58);
  while (value > BigInt.zero) {
    final remainder = (value % radix).toInt();
    encoded.add(_alphabet[remainder]);
    value ~/= radix;
  }

  var leadingZeros = 0;
  while (leadingZeros < bytes.length && bytes[leadingZeros] == 0) {
    leadingZeros++;
  }

  return '${List<String>.filled(leadingZeros, '1').join()}${encoded.reversed.join()}';
}
