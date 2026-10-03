import 'package:uuid/uuid.dart';
import 'package:id_generator/src/id_generator.dart';

class IdGeneratorRandom implements IdGenerator {
  final uuid = Uuid();

  @override
  String generateId() => uuid.v4();
}
