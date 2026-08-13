import 'package:cqrs/src/cqrs/exception/command_already_nacked_exception.dart';

// TODO: should this support any Object as nack value?
// String is rather limited and does not scale
final class CommandNacker {
  String? _message;

  String? get message => _message;

  void nack(String message) {
    if (_message != null) throw CommandAlreadyNackedException();
    _message = message;
  }
}
