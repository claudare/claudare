abstract class Encryption {
  Stream<List<int>> encrypt(Stream<List<int>> inputStream);
  Stream<List<int>> decrypt(Stream<List<int>> inputStream);
}
