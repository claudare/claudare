import 'package:id_generator/src/id_generator.dart';

class IdGeneratorStatic implements IdGenerator {
  final String _value;

  IdGeneratorStatic(this._value);

  @override
  String generateId() => _value;
}
