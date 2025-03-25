// need a sort of enum/union to make everything work without concrete implemntations
// there is a dart object called "key"
// all encryption keys needed for unlocking the file are stored as strings.
// they include a header, so that the algorithm can be identified from the key.

import 'package:core/src/encryption/common.dart';
import 'package:core/src/encryption/none.dart';
import 'package:core/src/encryption/aes256.dart';
import 'package:core/src/encryption/base64.dart';

const _algos = {
  'none': NoEncrytion,
  'base64': Base64Encoding,
  'aes256': AES256Encryption,
};

Encryption getEncryption(String name) {
  final algo = _algos[name];

  if (algo == null) {
    throw Exception('Encryption $name is not supported');
  }

  return algo as Encryption;
}
