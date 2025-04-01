import 'dart:math';

class FileSize {
  final int bytes;
  const FileSize(this.bytes);

  @override
  String toString() {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    if (bytes < 1024) return '$bytes ${units[0]}';
    int exp = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, exp)).toStringAsFixed(2)} ${units[exp]}';
  }
}
