import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/exception/command_codec_exception.dart';

class CommandCodecSafe {
  const CommandCodecSafe();

  EncodedCommand encode(CommandInput input) {
    var kind = input.runtimeType.toString();
    try {
      kind = input.kind;
      return EncodedCommand(kind: kind, bytes: input.encode());
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        CommandCodecException(
          'Failed to encode command of kind $kind',
          direction: CommandCodecDirection.encode,
          kind: kind,
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  CommandInput decode(EncodedCommand command) {
    throw UnimplementedError('Command decoding is not implemented');
  }
}
