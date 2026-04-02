import 'package:core/id_generator.dart';
import 'package:test/test.dart';

void main() {
  group('IdGenerator', () {
    test("secure random (default)", () {
      final generator = RandomIdGenerator();

      // bruteforce it
      for (var i = 0; i < 1000; i++) {
        generator.generateId();
        generator.generateBytes();
      }
    });

    test('seeded', () {
      final generator = RandomIdGenerator(randomSource: SeededRandomSource(0));

      expect(generator.generateId(), "jwEcs37HXgmZafciKLgzfg");
      expect(generator.generateId(), "we2AndvvXh2ESinwvOr-fg");
    });

    test('sequential', () {
      final generator = RandomIdGenerator(
        randomSource: SequentialRandomSource(),
      );

      expect(generator.generateId(), "AAAAAAAAAAAAAAAAAAAAAA");
      expect(generator.generateId(), "AAAAAAAAAAAAAAAAAAAAAQ");
      expect(generator.generateId(), "AAAAAAAAAAAAAAAAAAAAAg");
    });
  });
}
