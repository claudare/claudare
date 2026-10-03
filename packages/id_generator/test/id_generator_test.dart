import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';

void main() {
  group('IdGeneratorRandom', () {
    test('produces UUID v4 identifiers', () {
      final IdGenerator generator = IdGeneratorRandom();

      expect(
        generator.generateId(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('produces distinct identifiers', () {
      final IdGenerator generator = IdGeneratorRandom();

      final ids = List.generate(100, (_) => generator.generateId());

      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('IdGeneratorSequential', () {
    test('produces increasing decimal identifiers starting at one', () {
      final IdGenerator generator = IdGeneratorSequential();

      expect(List.generate(12, (_) => generator.generateId()), [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        '11',
        '12',
      ]);
    });

    test('keeps each generator sequence independent', () {
      final IdGenerator first = IdGeneratorSequential();
      final IdGenerator second = IdGeneratorSequential();

      first.generateId();
      first.generateId();

      expect(second.generateId(), '1');
    });
  });

  group('IdGeneratorStatic', () {
    for (final value in ['fixed-id', '1', '']) {
      test('repeats its configured value "$value"', () {
        final IdGenerator generator = IdGeneratorStatic(value);

        expect(generator.generateId(), value);
        expect(generator.generateId(), value);
      });
    }
  });
}
