import 'package:cqrs/src/cqrs/command/encoded_command.dart';

class StoredCommandWrite {
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;

  const StoredCommandWrite({
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
  });
}
