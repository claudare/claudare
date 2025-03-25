import 'dart:typed_data';

import 'package:core/src/blob_store/metadata.dart';
import 'package:test/test.dart';

void main() {
  group('BlobFile', () {
    test('should correctly read metadata and content from stream', () async {
      final metadata = BlobMetadata(10, 'application/octet-stream');
      final binaryData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      final contentStream = Stream.fromIterable([binaryData]);
      final testStream = BlobStreamWithMetadata.wrapContent(
        metadata,
        contentStream,
      );

      // Read back using fromStream
      final blobFile = await BlobStreamWithMetadata.fromRawStream(testStream);

      // Verify metadata
      expect(blobFile.metadata.plaintextLengthBytes, equals(10));
      expect(blobFile.metadata.mimeType, equals('application/octet-stream'));

      // Verify content
      final content = await blobFile.readUint8List();
      expect(content, equals(binaryData));
    });

    test('should handle empty content correctly', () async {
      final metadata = BlobMetadata(0, 'application/octet-stream');

      // Create a test stream with metadata and empty content
      final contentStream = Stream.fromIterable([Uint8List(0)]);
      final testStream = BlobStreamWithMetadata.wrapContent(
        metadata,
        contentStream,
      );

      final blobFile = await BlobStreamWithMetadata.fromRawStream(testStream);

      expect(blobFile.metadata.plaintextLengthBytes, equals(0));
      final content = await blobFile.readUint8List();
      expect(content, isEmpty);
    });

    test('should handle large binary content', () async {
      final largeData = Uint8List(1024 * 1024); // 1MB of data
      for (var i = 0; i < largeData.length; i++) {
        largeData[i] = i % 256; // Fill with repeating pattern
      }

      final metadata = BlobMetadata(
        largeData.length,
        'application/octet-stream',
      );

      // Split into chunks to simulate streaming
      final chunks = <Uint8List>[];
      const chunkSize = 64 * 1024; // 64KB chunks
      for (var i = 0; i < largeData.length; i += chunkSize) {
        final end =
            (i + chunkSize < largeData.length)
                ? i + chunkSize
                : largeData.length;
        chunks.add(largeData.sublist(i, end));
      }

      final contentStream = Stream.fromIterable(chunks);
      final testStream = BlobStreamWithMetadata.wrapContent(
        metadata,
        contentStream,
      );

      final blobFile = await BlobStreamWithMetadata.fromRawStream(testStream);

      expect(blobFile.metadata.plaintextLengthBytes, equals(largeData.length));

      final content = await blobFile.readUint8List();
      expect(content, equals(largeData));
    });

    test('should throw on invalid metadata', () async {
      // Create an invalid stream (missing newline)
      final invalidStream = Stream.fromIterable([
        Uint8List.fromList([1, 2, 3, 4, 5]),
      ]);

      expect(
        BlobStreamWithMetadata.fromRawStream(invalidStream),
        throwsA(isA<FormatException>()),
      );
    });

    test('should handle content size mismatch (underflow)', () async {
      final metadata = BlobMetadata(5, 'application/octet-stream');
      final tooMuchData = Uint8List.fromList([1, 2, 3, 4, 5, 6]); // 6 bytes

      final contentStream = Stream.fromIterable([tooMuchData]);
      final testStream = BlobStreamWithMetadata.wrapContent(
        metadata,
        contentStream,
      );
      final blobFile = await BlobStreamWithMetadata.fromRawStream(testStream);

      // final value = await blobFile.readUint8List();
      // print('value $value');
      expect(
        () async => await blobFile.readUint8List(),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle content size mismatch (overflow)', () async {
      final metadata = BlobMetadata(7, 'application/octet-stream');
      final tooMuchData = Uint8List.fromList([1, 2, 3, 4, 5, 6]); // 6 bytes

      final contentStream = Stream.fromIterable([tooMuchData]);
      final testStream = BlobStreamWithMetadata.wrapContent(
        metadata,
        contentStream,
      );
      final blobFile = await BlobStreamWithMetadata.fromRawStream(testStream);

      // final value = await blobFile.readUint8List();
      // print('value $value');
      expect(
        () async => await blobFile.readUint8List(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
