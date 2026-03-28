import 'package:core/src/cqrs/id_generator/id_generator.dart';

class FakeIdGeneratorSequential implements IdGenerator {
  int _counter = 0;

  @override
  String generateId() {
    return '${++_counter}';
  }
}
