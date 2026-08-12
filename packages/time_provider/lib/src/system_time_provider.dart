import 'time_provider.dart';

class SystemTimeProvider implements TimeProvider {
  @override
  DateTime now() {
    return DateTime.now();
  }
}
