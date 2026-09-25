import 'dart:typed_data';

import 'package:claudare_crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('static values use big-endian byte order', () {
    final key = PublicKey.staticValue(0x010203);

    expect(key.bytes, hasLength(publicKeyLength));
    expect(key.bytes.sublist(publicKeyLength - 3), [1, 2, 3]);
  });

  test('copies source bytes and exposes an unmodifiable view', () {
    final source = Uint8List(publicKeyLength)..[publicKeyLength - 1] = 1;
    final key = PublicKey(source);
    final originalByte = key.bytes.last;

    source[source.length - 1] = 2;

    expect(key.bytes.last, originalByte);
    expect(() => key.bytes[0] = 1, throwsUnsupportedError);
  });

  test('fromString validates the decoded key length', () {
    expect(() => PublicKey.fromString('2'), throwsArgumentError);
  });

  test('compares keys by their bytes in lexicographic order', () {
    final lower = PublicKey.staticValue(255);
    final higher = PublicKey.staticValue(256);

    expect(lower.compareTo(higher), lessThan(0));
    expect(lower, lessThan(higher));
    expect(lower, lessThanOrEqualTo(higher));
    expect(higher, greaterThan(lower));
    expect(higher, greaterThanOrEqualTo(lower));
  });

  test('keys with the same bytes are equal and have the same hash code', () {
    final first = PublicKey.staticValue(0x010203);
    final second = PublicKey.fromString(first.toString());

    expect(first, equals(second));
    expect(first.hashCode, equals(second.hashCode));
    expect(first.compareTo(second), 0);
  });

  test('keys with different bytes are unequal', () {
    expect(PublicKey.staticValue(1), isNot(PublicKey.staticValue(2)));
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
    expect(decoded, equals(key));
  });

  test('RoundTrips fromValue', () {
    final key = PublicKey.staticValue(0x010203);
    final encoded = key.toString();
    final decoded = PublicKey.fromString(encoded);
    expect(decoded, equals(key));
  });
}
