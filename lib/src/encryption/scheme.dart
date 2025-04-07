import 'package:core/src/encryption/common.dart';
import 'package:core/src/encryption/aes256.dart';
import 'package:core/src/encryption/fakecryption.dart';

sealed class AnyEncryptionScheme {
  const AnyEncryptionScheme();

  Encryptor get encryption;

  Map<String, dynamic> toJson();
  AnyEncryptionScheme.fromJson(Map<String, dynamic> json);

  static final Map<String, AnyEncryptionScheme Function(Map<String, dynamic>)>
  _parsers = {
    EncryptionSchemeFake.type: EncryptionSchemeFake.fromJson,
    EncryptionSchemeAES256.type: EncryptionSchemeAES256.fromJson,
  };

  static AnyEncryptionScheme anyFromJson(Map<String, dynamic> json) {
    if (_parsers.containsKey(json['type'])) {
      return _parsers[json['type']]!(json);
    }
    throw Exception('Unknown encryption type: ${json['type']}');
  }
}

class EncryptionSchemeFake extends AnyEncryptionScheme {
  static const type = 'fake';
  static const blockSize = Fakecryptor.chunkSize;

  final Fakecryptor _instance;

  const EncryptionSchemeFake(this._instance);

  @override
  Encryptor get encryption => _instance;

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'key': _instance.key.toHex()};
  }

  factory EncryptionSchemeFake.fromJson(Map<String, dynamic> json) {
    final key = FakecryptionKey.fromHex(json['key']);
    final instance = Fakecryptor(key);
    return EncryptionSchemeFake(instance);
  }
}

class EncryptionSchemeAES256 extends AnyEncryptionScheme {
  static const type = 'aes256';
  static const blockSize = EncryptorAES256.ivLength;

  final EncryptorAES256 _instance;

  const EncryptionSchemeAES256(this._instance);

  @override
  Encryptor get encryption => _instance;

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'key': _instance.key.toHex()};
  }

  factory EncryptionSchemeAES256.fromJson(Map<String, dynamic> json) {
    final key = AES256Key.fromHex(json['key']);
    final instance = EncryptorAES256(key);
    return EncryptionSchemeAES256(instance);
  }
}
