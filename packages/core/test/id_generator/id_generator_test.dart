import 'package:core/id_generator.dart';
import 'package:test/test.dart';

void main() {
  group('IdGeneratorSecure', () {
    test('produces 16-byte base64url identifiers', () {
      final IdGenerator generator = IdGeneratorSecure();

      final bytes = generator.generateBytes();
      final id = generator.generateId();

      expect(bytes, hasLength(IdGenerator.byteLength));
      expect(id, hasLength(IdGenerator.stringLength));
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(IdGenerator.stringToBytes(id), hasLength(IdGenerator.byteLength));
    });
  });

  group('IdGeneratorSeeded', () {
    test('produces deterministic identifiers', () {
      final IdGenerator generator = IdGeneratorSeeded(0);

      expect(generator.generateId(), 'jwEcs37HXgmZafciKLgzfg');
      expect(generator.generateId(), 'we2AndvvXh2ESinwvOr-fg');
    });
  });

  group('IdGeneratorSequential', () {
    test('produces fixed-width identifiers starting at zero', () {
      final IdGenerator generator = IdGeneratorSequential();

      expect(generator.generateId(), 'AAAAAAAAAAAAAAAAAAAAAA');
      expect(generator.generateId(), 'AAAAAAAAAAAAAAAAAAAAAQ');
      expect(generator.generateId(), 'AAAAAAAAAAAAAAAAAAAAAg');
    });

    test('produces 16-byte big-endian values', () {
      final IdGenerator generator = IdGeneratorSequential();

      expect(generator.generateBytes(), List<int>.filled(16, 0));
      expect(generator.generateBytes(), [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
      ]);
    });
  });

  group('IdGeneratorStatic', () {
    test('repeats its configured value', () {
      final IdGenerator generator = IdGeneratorStatic(1);

      expect(generator.generateId(), 'AAAAAAAAAAAAAAAAAAAAAQ');
      expect(generator.generateId(), 'AAAAAAAAAAAAAAAAAAAAAQ');
      expect(generator.generateBytes().last, 1);
      expect(generator.generateBytes().last, 1);
    });

    test('can set its configured value', () {
      final IdGenerator generator = IdGeneratorStatic(0)..set(2);

      expect(generator.generateId(), 'AAAAAAAAAAAAAAAAAAAAAg');
    });

    test('rejects negative values', () {
      expect(() => IdGeneratorStatic(-1), throwsRangeError);
      expect(() => IdGeneratorStatic(0)..set(-1), throwsRangeError);
    });

    test('rejects values greater than 128 bits', () {
      final dynamic tooLarge = BigInt.one << 128;

      expect(() => IdGeneratorStatic(tooLarge), throwsA(isA<TypeError>()));
      expect(
        () => IdGeneratorStatic(0)..set(tooLarge),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
