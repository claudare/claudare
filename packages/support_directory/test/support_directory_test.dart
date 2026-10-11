import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:support_directory/support_directory.dart';

void main() {
  late TempSupportDirectory base;
  late Directory root;
  late SupportDirectory support;

  setUp(() async {
    base = TempSupportDirectory();
    root = await base.getDirectory();
    support = SupportDirectory(
      namespace: 'dev',
      resolveBaseDirectory: () async => root,
    );
  });

  tearDown(() => base.delete());

  test('creates the namespace and missing parent directories', () async {
    final base = Directory(path.join(root.path, 'missing', 'support'));
    final nested = SupportDirectory(
      namespace: 'dev',
      resolveBaseDirectory: () async => base,
    );

    final directory = await nested.getDirectory();

    expect(directory.path, path.join(base.path, 'dev'));
    expect(await directory.exists(), isTrue);
  });

  test('file path resolves inside the namespace', () async {
    expect(
      await support.getFilePath('main.sqlite'),
      path.join(root.path, 'dev', 'main.sqlite'),
    );
  });

  test('file path access propagates resolver failures', () async {
    final failure = FileSystemException('unavailable');
    final directory = SupportDirectory(
      namespace: 'dev',
      resolveBaseDirectory: () async => throw failure,
    );

    await expectLater(
      directory.getFilePath('main.sqlite'),
      throwsA(same(failure)),
    );
  });

  test('namespaces resolve to separate directories', () async {
    final prod = SupportDirectory(
      namespace: 'prod',
      resolveBaseDirectory: () async => root,
    );

    expect((await support.getDirectory()).path, path.join(root.path, 'dev'));
    expect((await prod.getDirectory()).path, path.join(root.path, 'prod'));
  });

  test('deleting a namespace preserves siblings and root files', () async {
    await support.getDirectory();
    final sibling = await Directory(path.join(root.path, 'prod')).create();
    final siblingFile = File(path.join(sibling.path, 'main.sqlite'));
    final legacyFile = File(path.join(root.path, 'main.sqlite'));
    await siblingFile.writeAsString('prod');
    await legacyFile.writeAsString('legacy');

    await support.delete();

    expect(await siblingFile.readAsString(), 'prod');
    expect(await legacyFile.readAsString(), 'legacy');
  });

  test('deleting a missing namespace does not create it', () async {
    await support.delete();
    await support.delete();

    expect(await Directory(path.join(root.path, 'dev')).exists(), isFalse);
    expect(await root.list().toList(), isEmpty);
  });

  for (final namespace in [
    '',
    '.',
    '..',
    '../prod',
    '/prod',
    r'..\prod',
    r'C:\prod',
    'dev/prod',
    'dev prod',
    'dev\n',
  ]) {
    test('rejects invalid namespace ${namespace.replaceAll('\n', r'\n')}', () {
      expect(() => SupportDirectory(namespace: namespace), throwsArgumentError);
    });
  }

  for (final namespace in ['dev', 'prod', 'Test_1-2']) {
    test('accepts namespace $namespace', () async {
      final directory = SupportDirectory(
        namespace: namespace,
        resolveBaseDirectory: () async => root,
      );

      expect(
        (await directory.getDirectory()).path,
        path.join(root.path, namespace),
      );
    });
  }

  for (final delete in [false, true]) {
    test(
      '${delete ? 'delete' : 'getDirectory'} propagates resolver failures',
      () async {
        final failure = FileSystemException('unavailable');
        final directory = SupportDirectory(
          namespace: 'dev',
          resolveBaseDirectory: () async => throw failure,
        );

        await expectLater(
          delete ? directory.delete() : directory.getDirectory(),
          throwsA(same(failure)),
        );
      },
    );
  }

  test('propagates directory creation failures', () async {
    final file = File(path.join(root.path, 'dev'));
    await file.writeAsString('not a directory');

    await expectLater(
      support.getDirectory(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'not a directory');
  });
}
