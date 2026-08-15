import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/command_codec_safe.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:test/test.dart';

void main() {
  const codec = CommandCodecSafe();

  test('encodes a command input', () {
    final encoded = codec.encode(const _Input());

    expect(encoded.kind, 'test');
    expect(encoded.bytes, [1, 2, 3]);
  });

  test('decode is not implemented', () {
    expect(
      () => codec.decode(EncodedCommand(kind: 'test', bytes: Uint8List(0))),
      throwsUnimplementedError,
    );
  });
}

class _Input implements CommandInput {
  const _Input();

  @override
  String get kind => 'test';

  @override
  Uint8List encode() => Uint8List.fromList([1, 2, 3]);
}
