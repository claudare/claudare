import 'package:core/src/cqrs/exception/command_already_nacked_exception.dart';

final class CommandNacker {
  String? _message;

  String? get message => _message;

  void nack(String message) {
    if (_message != null) throw CommandAlreadyNackedException();
    _message = message;
  }
}
