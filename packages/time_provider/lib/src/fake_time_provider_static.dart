import 'time_provider.dart';

// time in the app is always using UTC time
class FakeTimeProviderStatic implements TimeProvider {
  final DateTime _value;

  FakeTimeProviderStatic(DateTime value) : _value = value.toUtc();

  FakeTimeProviderStatic.unixMilliseconds(int millisecondsSinceEpoch)
    : _value = DateTime.fromMillisecondsSinceEpoch(
        millisecondsSinceEpoch,
        isUtc: true,
      );

  factory FakeTimeProviderStatic.zero() {
    return FakeTimeProviderStatic.unixMilliseconds(0);
  }

  @override
  DateTime now() {
    return _value;
  }
}
