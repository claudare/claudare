import 'package:crdt/crdt_lww.dart';
import 'package:test/test.dart';

void main() {
  test('keeps value with a newer timestamp', () {
    final current = CrdtLwwValue('current', DateTime.utc(2100));
    current.applyChange(CrdtLwwChange('older', DateTime.utc(2000)));

    expect(current.value, 'current');
  });

  test('updates value with older timestamp', () {
    final current = CrdtLwwValue('current', DateTime.utc(2000));
    current.applyChange(CrdtLwwChange('newer', DateTime.utc(2100)));

    expect(current.value, 'newer');
  });

  test('handles tie breakers', () {
    final current = CrdtLwwValue('current', DateTime.utc(2000));
    current.applyChange(CrdtLwwChange('newer', DateTime.utc(2000)));

    expect(current.value, 'idk');
  }, skip: true);
}
