import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  const store = NoBlobStore();

  test('rejects blob reads', () {
    expect(() => store.get('blob'), throwsA(isA<UnsupportedError>()));
  });

  test('rejects blob writes', () {
    expect(
      () => store.save('blob', Uint8List.fromList([1])),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
