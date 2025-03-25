import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

Future<File> createTempFileWithContent(List<int> content) async {
  final directory = await Directory.systemTemp.createTemp('temp_test_');
  final file = File('${directory.path}/test_file');
  await file.writeAsBytes(content);

  // Add a cleanup step to delete the file after tests
  addTearDown(() async {
    try {
      await file.delete();
      await directory.delete();
    } catch (e) {
      // Ignore errors in cleanup
    }
  });

  return file;
}

Future<Uint8List> streamToUint8List(Stream<List<int>> stream) async {
  final List<int> chunks = await stream.fold(
    [],
    (previous, element) => previous..addAll(element),
  );
  return Uint8List.fromList(chunks);
}

/// creates a large random data
/// use 1024 * 1024 for 1MB
Uint8List generateLargeData(int size) {
  final largeData = Uint8List(size); // 1MB of data
  for (var i = 0; i < largeData.length; i++) {
    largeData[i] = i % 256; // Fill with repeating pattern
  }
  return largeData;
}

/// Splits the large file into chunks
/// use 64 * 1024 for 64 kb
List<Uint8List> splitIntoChunks(Uint8List largeData, int chunkSize) {
  final chunks = <Uint8List>[];
  for (var i = 0; i < largeData.length; i += chunkSize) {
    final end =
        (i + chunkSize < largeData.length) ? i + chunkSize : largeData.length;
    chunks.add(largeData.sublist(i, end));
  }

  return chunks;
}
