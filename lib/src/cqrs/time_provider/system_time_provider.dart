import 'package:core/src/cqrs/time_provider/time_provider.dart';

class SystemTimeProvider implements TimeProvider {
  @override
  DateTime now() {
    return DateTime.now();
  }
}
