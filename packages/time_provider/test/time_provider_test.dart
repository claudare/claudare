import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  group('SystemTimeProvider', () {
    test('reads the system clock', () {
      final TimeProvider timeProvider = SystemTimeProvider();
      final before = DateTime.now();

      final now = timeProvider.now();

      final after = DateTime.now();
      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
    });
  });

  group('FakeTimeProviderStatic', () {
    test('normalizes its value to UTC', () {
      final TimeProvider timeProvider = FakeTimeProviderStatic(
        DateTime.parse('2026-08-12T12:00:00+02:00'),
      );

      expect(timeProvider.now(), DateTime.utc(2026, 8, 12, 10));
      expect(timeProvider.now().isUtc, isTrue);
    });

    test('creates a UTC value from Unix milliseconds', () {
      final TimeProvider timeProvider = FakeTimeProviderStatic.unixMilliseconds(
        1000,
      );

      expect(
        timeProvider.now(),
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
    });

    test('provides the Unix epoch as zero', () {
      final TimeProvider timeProvider = FakeTimeProviderStatic.zero();

      expect(
        timeProvider.now(),
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });
}
