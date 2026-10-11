import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:support_directory/support_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late TempSupportDirectory base;
  late Directory root;
  late SupportDirectory support;
  PlatformException? platformFailure;

  setUp(() async {
    base = TempSupportDirectory();
    root = Directory(path.join((await base.getDirectory()).path, 'support'));
    support = PathProviderSupportDirectory();
    platformFailure = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      if (platformFailure != null) throw platformFailure!;
      return root.path;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await base.delete();
  });

  test('creates the support root and missing parent directories', () async {
    root = Directory(path.join(root.path, 'missing', 'support'));

    final directory = await support.getDirectory();

    expect(directory.path, root.path);
    expect(await directory.exists(), isTrue);
  });

  test('file path resolves directly inside the support root', () async {
    expect(
      await support.getFilePath('main.sqlite'),
      path.join(root.path, 'main.sqlite'),
    );
  });

  test('deleting a missing support root does not create it', () async {
    await support.delete();

    expect(await root.exists(), isFalse);
  });

  final operations = <String, Future<void> Function()>{
    'getDirectory': () async {
      await support.getDirectory();
    },
    'getFilePath': () async {
      await support.getFilePath('main.sqlite');
    },
    'delete': () => support.delete(),
  };
  for (final operation in operations.entries) {
    test('${operation.key} propagates platform failures', () async {
      platformFailure = PlatformException(code: 'unavailable');

      await expectLater(
        operation.value(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    });
  }

  test('propagates directory creation failures', () async {
    final file = File(root.path);
    await file.writeAsString('not a directory');

    await expectLater(
      support.getDirectory(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'not a directory');
  });
}
