import 'package:blob/src/path.dart';
import 'package:test/test.dart';

void main() {
  test('converts between blob IDs and stream paths', () {
    expect(blobStream('one'), '_blob/one');
    expect(blobIdFromStream(blobStream('one')), 'one');
  });

  test('rejects invalid blob stream paths', () {
    for (final path in ['', '_blob/', 'other/one']) {
      expect(() => blobIdFromStream(path), throwsFormatException);
    }
  });
}
