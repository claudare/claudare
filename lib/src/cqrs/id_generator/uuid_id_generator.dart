import 'package:core/src/cqrs/id_generator/id_generator.dart';
import 'package:uuid/uuid.dart';

class UuidIdGenerator implements IdGenerator {
  final _uuid = Uuid();

  UuidIdGenerator();

  @override
  String generateId() {
    return _uuid.v4();
  }
}
