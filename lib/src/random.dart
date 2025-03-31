import 'dart:math';

int randomU64() {
  final random = Random.secure();
  // Generate two 32-bit integers and combine them into a 64-bit integer
  int highBits = random.nextInt(1 << 32);
  int lowBits = random.nextInt(1 << 32);
  return (highBits << 32) | lowBits;
}
