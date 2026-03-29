import 'id_generator.dart';

class FakeIdGeneratorSequential implements IdGenerator {
  int _counter = 0;

  @override
  String generateId() {
    return '${++_counter}';
  }
}
