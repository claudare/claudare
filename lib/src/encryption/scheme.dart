import 'package:core/src/encryption/common.dart';
import 'package:core/src/encryption/aes256.dart';
import 'package:core/src/encryption/fake.dart';

sealed class EncryptionAnyScheme {
  const EncryptionAnyScheme();

  Encryptor get encryptor;

  Map<String, dynamic> toJson();

  static final Map<String, EncryptionAnyScheme Function(Map<String, dynamic>)>
  _parsers = {
    EncryptionSchemeFake.type: EncryptionSchemeFake.fromJson,
    EncryptionSchemeAES256.type: EncryptionSchemeAES256.fromJson,
  };

  static EncryptionAnyScheme fromJson(Map<String, dynamic> json) {
    if (_parsers.containsKey(json['type'])) {
      return _parsers[json['type']]!(json);
    }
    throw Exception('Unknown encryption type: ${json['type']}');
  }
}

class EncryptionSchemeFake extends EncryptionAnyScheme {
  static const type = 'fake';
  static const blockSize = EncryptorFake.chunkSize;

  final EncryptionKeyFake _key;

  const EncryptionSchemeFake(this._key);

  @override
  Encryptor get encryptor => _key.encryptor;

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'key': _key.toHex()};
  }

  factory EncryptionSchemeFake.fromJson(Map<String, dynamic> json) {
    final key = EncryptionKeyFake.fromHex(json['key']);
    return EncryptionSchemeFake(key);
  }
}

class EncryptionSchemeAES256 extends EncryptionAnyScheme {
  static const type = 'aes256';
  static const blockSize = EncryptorAes256.ivLength;

  final EncryptionKeyAes256 _key;

  const EncryptionSchemeAES256(this._key);

  @override
  Encryptor get encryptor => _key.encryptor;

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'key': _key.toHex()};
  }

  factory EncryptionSchemeAES256.fromJson(Map<String, dynamic> json) {
    final key = EncryptionKeyAes256.fromHex(json['key']);
    return EncryptionSchemeAES256(key);
  }
}
