import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:support_directory/support_directory.dart';

void main() {
  late TempSupportDirectory support;

  setUp(() => support = TempSupportDirectory());
  tearDown(() => support.delete());

  test('allocates a directory within the system temporary directory', () async {
    final directory = await support.getDirectory();

    expect(path.isWithin(Directory.systemTemp.path, directory.path), isTrue);
  });

  test('instances receive separate directories', () async {
    final second = TempSupportDirectory();
    addTearDown(second.delete);

    final firstDirectory = await support.getDirectory();
    final secondDirectory = await second.getDirectory();

    expect(firstDirectory.path, isNot(secondDirectory.path));
  });

  test('deleting one instance preserves another instance', () async {
    final second = TempSupportDirectory();
    addTearDown(second.delete);
    await support.getDirectory();
    final file = File(await second.getFilePath('data'));
    await file.writeAsString('saved');

    await support.delete();

    expect(await file.readAsString(), 'saved');
  });

  test('concurrent first accesses share one allocation', () async {
    final directories = await Future.wait(
      List.generate(10, (_) => support.getDirectory()),
    );

    expect(
      directories.map((directory) => directory.path).toSet(),
      hasLength(1),
    );
    expect(await directories.first.exists(), isTrue);
  });

  test('deletion waits for initial allocation', () async {
    final accessing = support.getDirectory();
    final deleting = support.delete();
    final directory = await accessing;
    await deleting;

    expect(await directory.exists(), isFalse);
  });
}
