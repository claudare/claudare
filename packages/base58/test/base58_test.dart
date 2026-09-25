import 'dart:typed_data';

// ignore: avoid_relative_lib_imports
import '../lib/base58.dart';
import 'package:test/test.dart';

void main() {
  group('base58Encode', () {
    test('encodes the standard Base58 vector', () {
      expect(base58Encode('Hello World!'.codeUnits), '2NEpo7TZRRrLZSi2U');
    });

    test('preserves leading zero bytes', () {
      expect(base58Encode([0, 0, 1]), '112');
      expect(base58Encode([0, 0]), '11');
    });

    test('encodes empty bytes as an empty string', () {
      expect(base58Encode([]), '');
    });

    test('rejects values outside the byte range', () {
      expect(() => base58Encode([-1]), throwsArgumentError);
      expect(() => base58Encode([256]), throwsArgumentError);
    });
  });

  group('base58Decode', () {
    test('decodes the standard Base58 vector', () {
      expect(base58Decode('2NEpo7TZRRrLZSi2U'), 'Hello World!'.codeUnits);
    });

    test('preserves leading zero bytes', () {
      expect(base58Decode('112'), [0, 0, 1]);
      expect(base58Decode('11'), [0, 0]);
      expect(base58Decode('1'), [0]);
    });

    test('decodes empty input as empty bytes', () {
      expect(
        base58Decode(''),
        isA<Uint8List>().having((v) => v, 'bytes', isEmpty),
      );
    });

    test('rejects characters outside the Base58 alphabet', () {
      expect(() => base58Decode('0'), throwsFormatException);
      expect(() => base58Decode('O'), throwsFormatException);
      expect(() => base58Decode('I'), throwsFormatException);
      expect(() => base58Decode('l'), throwsFormatException);
    });
  });

  test('round trips arbitrary byte sequences', () {
    final vectors = <List<int>>[
      [],
      [0],
      [0, 0, 255, 0, 128],
      List<int>.generate(256, (i) => i),
    ];

    for (final bytes in vectors) {
      expect(base58Decode(base58Encode(bytes)), bytes);
    }
  });
}
