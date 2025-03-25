import 'package:core/src/encryption/common.dart';
import 'package:core/src/encryption/none.dart';
import 'package:core/src/encryption/aes256.dart';
import 'package:core/src/encryption/base64.dart';

const _algos = {
  'none': NoEncrytion,
  'base64': Base64Encoding,
  'aes256': AES256Encryption,
};

Encryption encryptionFromName(String name) {
  final algo = _algos[name];

  if (algo == null) {
    throw Exception('Encryption $name is not supported');
  }

  return algo as Encryption;
}

List<String> encryptionSupported() {
  return _algos.keys.toList();
}
