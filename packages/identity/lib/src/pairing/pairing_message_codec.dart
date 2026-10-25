// import 'dart:convert';

// TODO
// import 'pairing_message.dart';

// Encodes [PairingMessage]s as JSON strings with base64 blob bytes.
// class PairingMessageCodec extends Codec<PairingMessage, String> {
//   const PairingMessageCodec();
//
//   @override
//   Converter<String, PairingMessage> get decoder =>
//       const _BlobReplicationMessageDecoder();
//
//   @override
//   Converter<PairingMessage, String> get encoder =>
//       const _BlobReplicationMessageEncoder();
// }
//
// class _BlobReplicationMessageEncoder extends Converter<PairingMessage, String> {
//   const _BlobReplicationMessageEncoder();
//
//   @override
//   String convert(PairingMessage input) => jsonEncode(input.toJson());
//
//   @override
//   Stream<String> bind(Stream<PairingMessage> stream) => stream.map(convert);
// }
//
// class _BlobReplicationMessageDecoder extends Converter<String, PairingMessage> {
//   const _BlobReplicationMessageDecoder();
//
//   @override
//   PairingMessage convert(String input) =>
//       PairingMessage.fromJson(jsonDecode(input));
//
//   @override
//   Stream<PairingMessage> bind(Stream<String> stream) => stream.map(convert);
// }
