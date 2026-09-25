import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  group('Dot', () {
    test('accepts unrestricted integer actor ids and positive sequences', () {
      expect(Dot(-100, 1).actorId, -100);
      expect(Dot(1 << 80, 2).actorId, 1 << 80);
      expect(() => Dot(0, 0), throwsFormatException);
      expect(() => Dot(0, -1), throwsFormatException);
    });

    test('round trips JSON', () {
      final dot = Dot(-3, 8);
      expect(Dot.fromJson(dot.toJson()), dot);
      expect(dot.toString(), 'Dot(actorId: -3, sequence: 8)');
    });

    test('uses actor terminology for malformed JSON', () {
      expect(
        () => Dot.fromJson([1]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'dot must contain actor id and sequence',
          ),
        ),
      );
    });
  });

  group('VersionVector', () {
    test('compares causal dependencies and advances without holes', () {
      final dependency = VersionVector({2: 4, -1: 3});
      final frontier = VersionVector({-1: 3, 2: 5});
      expect(frontier.contains(dependency), isTrue);
      expect(dependency.contains(frontier), isFalse);
      expect(frontier.advance(Dot(-1, 4)).value(-1), 4);
      expect(() => frontier.advance(Dot(-1, 5)), throwsStateError);
    });

    test('serializes integer keys deterministically', () {
      final vector = VersionVector({3: 2, -1: 4, 100: 1});
      expect(vector.toJson(), [
        [-1, 4],
        [3, 2],
        [100, 1],
      ]);
      expect(VersionVector.fromJson(vector.toJson()), vector);
    });
  });
}
