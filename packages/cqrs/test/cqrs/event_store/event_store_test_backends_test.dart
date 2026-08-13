import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} test backend', () {
      test('closes idempotently', () async {
        final session = await backend.open();

        await session.close();
        await session.close();
      });
    });
  }
}
