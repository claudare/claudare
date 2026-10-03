import 'package:id_generator/src/id_generator.dart';

class IdGeneratorSequential implements IdGenerator {
  int _value = 0;

  @override
  String generateId() => (++_value).toString();
}
