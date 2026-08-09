import 'package:crdt/crdt.dart';
import 'package:test/test.dart';

void main() {
  test('zero values use the UTC epoch', () {
    final dateTimePair = CrdtValueDateTimePair.zero('value');
    final latestWriteWins = CrdtValueLatestWriteWins.zero('value');

    expect(
      dateTimePair.occurredAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(
      latestWriteWins.occurredAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test('merge keeps a value with a newer timestamp', () {
    final current = CrdtValueLatestWriteWins('current', DateTime.utc(2026));

    expect(current.merge('older', DateTime.utc(2025)), same(current));
  });

  test('merge replaces a value with an equal or newer timestamp', () {
    final occurredAt = DateTime.utc(2026);
    final current = CrdtValueLatestWriteWins('current', occurredAt);

    final equal = current.merge('equal', occurredAt);
    final newer = current.merge('newer', DateTime.utc(2027));

    expect(equal.value, 'equal');
    expect(equal.occurredAt, occurredAt);
    expect(newer.value, 'newer');
    expect(newer.occurredAt, DateTime.utc(2027));
  });

  test('mergePair delegates to timestamp-based merging', () {
    final current = CrdtValueLatestWriteWins('current', DateTime.utc(2026));
    final incoming = CrdtValueDateTimePair('incoming', DateTime.utc(2027));

    final merged = current.mergePair(incoming);

    expect(merged.value, 'incoming');
    expect(merged.occurredAt, DateTime.utc(2027));
  });
}
