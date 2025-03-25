import 'package:core/src/encryption/common.dart';

class NoEncrytion extends Encryption {
  @override
  Stream<List<int>> decrypt(Stream<List<int>> inputStream) => inputStream;

  @override
  Stream<List<int>> encrypt(Stream<List<int>> inputStream) => inputStream;
}
