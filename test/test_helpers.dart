import 'dart:io';

import 'package:test/test.dart';

Future<File> createTempFileWithContent(List<int> content) async {
  final directory = await Directory.systemTemp.createTemp('blob_file_test_');
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
