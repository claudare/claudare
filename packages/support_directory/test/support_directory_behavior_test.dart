import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:support_directory/support_directory.dart';

void main() {
  for (final temporary in [false, true]) {
    group(temporary ? 'temporary' : 'platform', () {
      late TempSupportDirectory base;
      late SupportDirectory support;

      setUp(() {
        base = TempSupportDirectory();
        support = temporary
            ? TempSupportDirectory()
            : SupportDirectory(
                namespace: 'dev',
                resolveBaseDirectory: base.getDirectory,
              );
      });

      tearDown(() async {
        await support.delete();
        await base.delete();
      });

      test('repeated access preserves existing contents', () async {
        final directory = await support.getDirectory();
        final file = File(path.join(directory.path, 'existing'));
        await file.writeAsString('saved');

        expect((await support.getDirectory()).path, directory.path);
        expect(await file.readAsString(), 'saved');
      });

      test('file path resolves inside the owned directory', () async {
        final filepath = await support.getFilePath('main.sqlite');

        expect(
          filepath,
          path.join((await support.getDirectory()).path, 'main.sqlite'),
        );
      });

      test('file path access creates its directory', () async {
        final filepath = await support.getFilePath('main.sqlite');

        expect(await Directory(path.dirname(filepath)).exists(), isTrue);
      });

      test('file path access does not create the file', () async {
        final filepath = await support.getFilePath('main.sqlite');

        expect(await File(filepath).exists(), isFalse);
      });

      test('file path access preserves an existing file', () async {
        final filepath = await support.getFilePath('main.sqlite');
        await File(filepath).writeAsString('saved');

        await support.getFilePath('main.sqlite');

        expect(await File(filepath).readAsString(), 'saved');
      });

      test('deletes the directory and nested contents', () async {
        final directory = await support.getDirectory();
        final nested = await Directory(path.join(directory.path, 'nested'))
            .create();
        final file = File(path.join(nested.path, 'data'));
        await file.writeAsString('saved');

        await support.delete();

        expect(await directory.exists(), isFalse);
        expect(await file.exists(), isFalse);
      });

      test('deletion before access leaves the instance usable', () async {
        await support.delete();

        expect(await (await support.getDirectory()).exists(), isTrue);
      });

      test('repeated deletion leaves the directory absent', () async {
        final directory = await support.getDirectory();
        await support.delete();

        await support.delete();

        expect(await directory.exists(), isFalse);
      });

      test('access recreates the same path after deletion', () async {
        final directory = await support.getDirectory();
        await support.delete();

        final recreated = await support.getDirectory();

        expect(recreated.path, directory.path);
        expect(await recreated.exists(), isTrue);
      });
    });
  }
}
