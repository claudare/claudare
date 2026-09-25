import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  test('applies the greatest sequence for each actor', () {
    final vector = VersionVectorMutating()
      ..apply(Dot(1, 2))
      ..apply(Dot(2, 3))
      ..apply(Dot(1, 1))
      ..apply(Dot(1, 2))
      ..apply(Dot(1, 4));

    expect(vector.toVersionVector(), VersionVector({1: 4, 2: 3}));
  });

  test('returns immutable snapshots', () {
    final vector = VersionVectorMutating()..apply(Dot(1, 1));
    final snapshot = vector.toVersionVector();

    vector.apply(Dot(1, 2));

    expect(snapshot, VersionVector({1: 1}));
    expect(vector.toVersionVector(), VersionVector({1: 2}));
  });
}
