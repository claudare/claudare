import 'package:core/src/encryption/common.dart';
import 'package:core/src/encryption/aes256.dart';
import 'package:core/src/encryption/base64.dart';

sealed class AnyEncryptionScheme {
  const AnyEncryptionScheme();

  Encryption get encryption;

  Map<String, dynamic> toJson();
  AnyEncryptionScheme.fromJson(Map<String, dynamic> json);

  static final Map<String, AnyEncryptionScheme Function(Map<String, dynamic>)>
  _parsers = {
    EncryptionSchemeBase64.type: EncryptionSchemeBase64.fromJson,
    EncryptionSchemeAES256.type: EncryptionSchemeAES256.fromJson,
  };

  static AnyEncryptionScheme anyFromJson(Map<String, dynamic> json) {
    if (_parsers.containsKey(json['type'])) {
      return _parsers[json['type']]!(json);
    }
    throw Exception('Unknown encryption type: ${json['type']}');
  }
}

class EncryptionSchemeBase64 extends AnyEncryptionScheme {
  static const type = 'base64';
  static const blockSize = Base64Encoding.chunkSize;

  @override
  Encryption get encryption => Base64Encoding();

  @override
  Map<String, dynamic> toJson() {
    return {'type': type};
  }

  const EncryptionSchemeBase64.fromJson(Map<String, dynamic> json);
}

class EncryptionSchemeAES256 extends AnyEncryptionScheme {
  static const type = 'aes256';
  static const blockSize = AES256Encryption.ivLength;

  final AES256Encryption _instance;

  const EncryptionSchemeAES256(this._instance);

  @override
  Encryption get encryption => _instance;

  @override
  Map<String, dynamic> toJson() {
    return {'type': type, 'key': _instance.key.toHex()};
  }

  factory EncryptionSchemeAES256.fromJson(Map<String, dynamic> json) {
    final key = AES256Key.fromHex(json['key']);
    final instance = AES256Encryption(key);
    return EncryptionSchemeAES256(instance);
  }
}
