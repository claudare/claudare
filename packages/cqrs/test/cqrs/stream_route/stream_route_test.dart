import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  group('StreamRouteWildcard', () {
    final route = StreamRouteWildcard('account/*');

    test('builds stream paths', () {
      expect(route.buildPath('123'), 'account/123');
    });

    test('matches paths without another route instance', () {
      expect(route.matches('account/123'), isTrue);
      expect(route.matches('accounting/123'), isFalse);
      expect(route.matches('user/123'), isFalse);
    });
  });

  test('StreamRouteAll passes paths through and matches every path', () {
    const route = StreamRouteAll();

    expect(route.buildPath('account/123'), 'account/123');
    expect(route.matches('account/123'), isTrue);
    expect(route.matches(''), isTrue);
  });
}
