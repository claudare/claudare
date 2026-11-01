import 'dart:io';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileBlobStore storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file_blob_storage_');
    storage = FileBlobStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('stores a blob using its ID as the filename', () async {
    await storage.save('blob-id', Uint8List.fromList([1, 2, 3]));

    final file = File('${directory.path}${Platform.pathSeparator}blob-id');
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('lists and deletes blobs when the directory does not exist', () async {
    final missing = FileBlobStore(Directory('${directory.path}/missing'));

    expect(await missing.listIds(), isEmpty);
    await missing.delete('absent');
  });
}
