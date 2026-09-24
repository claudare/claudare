import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  test('load returns null before a snapshot is saved', () async {
    final snapshotter = MemorySnapshotter<_MutableState>();

    expect(await snapshotter.load(1), isNull);
  });

  test('save and load preserve state and sequence', () async {
    final snapshotter = MemorySnapshotter<_MutableState>();
    await snapshotter.save(3, Snapshot(_MutableState([1, 2]), 7));

    final loaded = await snapshotter.load(3);

    expect(loaded, isNotNull);
    expect(loaded!.sequence, 7);
    expect(loaded.state.values, [1, 2]);
  });

  test('save isolates the stored state from caller mutations', () async {
    final snapshotter = MemorySnapshotter<_MutableState>();
    final state = _MutableState([1]);
    await snapshotter.save(1, Snapshot(state, 4));

    state.values.add(2);

    expect((await snapshotter.load(1))!.state.values, [1]);
  });

  test('each load returns state detached from the stored snapshot', () async {
    final snapshotter = MemorySnapshotter<_MutableState>();
    await snapshotter.save(1, Snapshot(_MutableState([1]), 4));

    final first = (await snapshotter.load(1))!;
    first.state.values.add(2);
    final second = (await snapshotter.load(1))!;

    expect(second.state.values, [1]);
    expect(second, isNot(same(first)));
    expect(second.state, isNot(same(first.state)));
  });

  test('load returns null for a different aggregate version', () async {
    final snapshotter = MemorySnapshotter<_MutableState>();
    await snapshotter.save(1, Snapshot(_MutableState([1]), 4));

    expect(await snapshotter.load(2), isNull);
    expect((await snapshotter.load(1))!.state.values, [1]);
  });

  test('a later save replaces the snapshot and version', () async {
    final snapshotter = MemorySnapshotter<_MutableState>();
    await snapshotter.save(1, Snapshot(_MutableState([1]), 4));
    await snapshotter.save(2, Snapshot(_MutableState([2]), 8));

    expect(await snapshotter.load(1), isNull);
    final loaded = (await snapshotter.load(2))!;
    expect(loaded.state.values, [2]);
    expect(loaded.sequence, 8);
  });

  test('separate instances retain independent snapshots', () async {
    final first = MemorySnapshotter<_MutableState>();
    final second = MemorySnapshotter<_MutableState>();
    await first.save(1, Snapshot(_MutableState([1]), 4));
    await second.save(1, Snapshot(_MutableState([2]), 5));

    expect((await first.load(1))!.state.values, [1]);
    expect((await second.load(1))!.state.values, [2]);
  });
}

final class _MutableState implements SnapshotCloneable<_MutableState> {
  final List<int> values;

  _MutableState(Iterable<int> values) : values = List.of(values);

  @override
  _MutableState clone() => _MutableState(values);
}
