import 'dart:io';

import 'package:notes/application/fake_application_factory.dart';
import 'package:test/test.dart';

void main() {
  test('initializes', () async {
    final applicationDirectory = await Directory.systemTemp.createTemp(
      'notes-application-test-',
    );
    final application = FakeApplicationFactory().create();
    addTearDown(() async {
      await application.searchDb.close();
      await application.sqliteDb.close();
      await applicationDirectory.delete(recursive: true);
    });

    await application.initialize(applicationDirectory.path);
  });
}
