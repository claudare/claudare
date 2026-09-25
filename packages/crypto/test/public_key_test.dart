import 'package:claudare_crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('static values use big-endian byte order', () {
    final key = PublicKey.staticValue(0x010203);

    expect(key.bytes, hasLength(publicKeyLength));
    expect(key.bytes.sublist(publicKeyLength - 3), [1, 2, 3]);
  });

  test('zero value has the correct bytes', () {
    final key = PublicKey.staticValue(0);
    final encoded = key.toString();

    expect(key.bytes, everyElement(0));
    expect(PublicKey.fromString(encoded).bytes, equals(key.bytes));
  });

  test('RoundTrips random', () {
    final key = PublicKey.secureRandom();
    final encoded = key.toString();
    final decoded = PublicKey.fromString(encoded);
    expect(decoded.bytes, equals(key.bytes));
  });

  test('RoundTrips fromValue', () {
    final key = PublicKey.staticValue(0x010203);
    final encoded = key.toString();
    final decoded = PublicKey.fromString(encoded);
    expect(decoded.bytes, equals(key.bytes));
  });
}
