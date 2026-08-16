import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  group('StreamRouteWildcard', () {
    final route = StreamRouteWildcard('account/*');

    test('builds and parses stream paths', () {
      expect(route.buildPath('123'), 'account/123');
      expect(route.parseParams('account/123'), '123');
    });

    test('matches paths without another route instance', () {
      expect(route.matches('account/123'), isTrue);
      expect(route.matches('accounting/123'), isFalse);
      expect(route.matches('user/123'), isFalse);
    });

    test('rejects parsing a non-matching path', () {
      expect(
        () => route.parseParams('user/123'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'streamPath',
          ),
        ),
      );
    });
  });

  test('StreamRouteAll passes paths through and matches every path', () {
    const route = StreamRouteAll();

    expect(route.buildPath('account/123'), 'account/123');
    expect(route.parseParams('account/123'), 'account/123');
    expect(route.matches('account/123'), isTrue);
    expect(route.matches(''), isTrue);
  });
}
