import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  test('initialization serializes to the proxy headers', () {
    const init = ProxyInit(actor: 'actor', group: 'group');

    expect(init.toHeaders(), {
      'claudare-actor': 'actor',
      'claudare-group': 'group',
    });
  });

  test('initialization preserves values through a header round trip', () {
    const original = ProxyInit(actor: ' actor ', group: ' group ');

    final decoded = ProxyInit.fromHeaders(original.toHeaders());

    expect(decoded.actor, original.actor);
    expect(decoded.group, original.group);
  });

  for (final header in ['claudare-actor', 'claudare-group']) {
    test('missing $header throws FormatException', () {
      final headers = const ProxyInit(
        actor: 'actor',
        group: 'group',
      ).toHeaders()..remove(header);

      expect(() => ProxyInit.fromHeaders(headers), throwsFormatException);
    });

    for (final value in ['', ' \t\n ']) {
      test(
        'blank $header ${value.isEmpty ? 'empty' : 'whitespace'} is rejected',
        () {
          final headers = const ProxyInit(
            actor: 'actor',
            group: 'group',
          ).toHeaders()..[header] = value;

          expect(() => ProxyInit.fromHeaders(headers), throwsFormatException);
        },
      );
    }
  }
}
