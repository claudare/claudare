import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/src/encryption/aes256.dart';
import 'package:core/src/encryption/fake.dart';

import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('Encryption table tests', () {
    final fakeKey = EncryptionKeyFake.notSoRandom(DeviceId(0));
    final aesKey = EncryptionKeyAes256.secureRandom();
    final algoBase64 = EncryptorFake(fakeKey);
    final algoAes265 = EncryptorAes256(aesKey);
    final algos = [('fake', 64, algoBase64), ('aes256', 16, algoAes265)];

    for (final (name, blockSize, algo) in algos) {
      test('round-trip at block size - $name', () async {
        final cleartextData = Uint8List.fromList(
          List<int>.generate(blockSize, (i) => i),
        );

        final cleartextStream = Stream.fromIterable([cleartextData]);
        final encryptionStream = algo.encrypt(cleartextStream);

        final encryptedData = await streamToUint8List(encryptionStream);
        expect(encryptedData, isNot(equals(cleartextData)));

        final encryptedStream = Stream.fromIterable([encryptedData]);
        final decryptedStream = algo.decrypt(encryptedStream);
        final decryptedData = await streamToUint8List(decryptedStream);

        expect(decryptedData, equals(cleartextData));
      });

      test('round-trip shorter then block - $name', () async {
        // small payload (under 16 bytes, odd size)
        final cleartextData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);

        final cleartextStream = Stream.fromIterable([cleartextData]);
        final encryptionStream = algo.encrypt(cleartextStream);

        final encryptedData = await streamToUint8List(encryptionStream);
        expect(cleartextData, isNot(equals(encryptedData)));

        final encryptedStream = Stream.fromIterable([encryptedData]);
        final decryptedStream = algo.decrypt(encryptedStream);
        final decryptedData = await streamToUint8List(decryptedStream);

        expect(cleartextData, equals(decryptedData));
      });

      test('round-trip short chunks - $name', () async {
        final cleartextData = Uint8List.fromList([1, 2, 3, 4, 5]);

        // two small chunks are passed
        final cleartextStream = Stream.fromIterable([
          cleartextData,
          cleartextData,
        ]);
        final encryptionStream = algo.encrypt(cleartextStream);

        final encryptedData = await streamToUint8List(encryptionStream);
        // expect(cleartextData, isNot(equals(encryptedData)));

        final encryptedStream = Stream.fromIterable([encryptedData]);
        final decryptedStream = algo.decrypt(encryptedStream);
        final decryptedData = await streamToUint8List(decryptedStream);

        expect(cleartextData, equals(decryptedData.sublist(0, 5)));
        expect(cleartextData, equals(decryptedData.sublist(5, 10)));
      });

      test('round-trip 64kb chunks - $name', () async {
        final cleartextData = generateLargeData(100 * 1024); // 100kb

        final cleartextStream = Stream.fromIterable(
          splitIntoChunks(cleartextData, 64 * 1024),
        );
        final encryptionStream = algo.encrypt(cleartextStream);

        final encryptedData = await streamToUint8List(encryptionStream);
        expect(cleartextData, isNot(equals(encryptedData)));

        final encryptedStream = Stream.fromIterable(
          splitIntoChunks(encryptedData, 64 * 1024),
        );
        final decryptedStream = algo.decrypt(encryptedStream);
        final decryptedData = await streamToUint8List(decryptedStream);

        expect(cleartextData, equals(decryptedData));
      });
    }
  });
}
