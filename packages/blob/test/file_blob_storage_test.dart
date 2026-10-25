import 'dart:io';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileBlobStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file_blob_storage_');
    storage = FileBlobStorage(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('stores a blob using its ID as the filename', () async {
    await storage.save('blob-id', Uint8List.fromList([1, 2, 3]));

    final file = File('${directory.path}${Platform.pathSeparator}blob-id');
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
}
