import 'dart:convert';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  final time = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);
  final later = DateTime.fromMillisecondsSinceEpoch(200, isUtc: true);

  BundledEvent event(
    String path,
    List<int> bytes, {
    String kind = 'test',
    DateTime? at,
  }) => BundledEvent(
    streamPath: path,
    encodedEvent: EncodedEvent(kind: kind, bytes: Uint8List.fromList(bytes)),
    occuredAt: at ?? time,
  );

  CommandBundle bundle({
    CommandId? id,
    VersionVector? dependency,
    DateTime? at,
    List<BundledEvent>? events,
  }) => CommandBundle(
    commandId: id ?? CommandId(2, 1),
    dependency: dependency ?? VersionVector({1: 3}),
    occuredAt: at ?? time,
    events:
        events ??
        [
          event('one', [1, 2]),
          event('two', [3]),
        ],
  );

  test('equivalent bundles have equal hashes with distinct values', () {
    final first = bundle();
    final second = bundle();

    expect(identical(first, second), isFalse);
    expect(identical(first.events.first, second.events.first), isFalse);
    expect(
      identical(
        first.events.first.encodedEvent.bytes,
        second.events.first.encodedEvent.bytes,
      ),
      isFalse,
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect({first, second}, hasLength(1));
  });

  test('metadata, event content, and order affect equality', () {
    final original = bundle();
    final variants = [
      bundle(id: CommandId(2, 2)),
      bundle(dependency: VersionVector({1: 4})),
      bundle(at: later),
      bundle(
        events: [
          event('one', [9, 2]),
          event('two', [3]),
        ],
      ),
      bundle(
        events: [
          event('one', [1, 2], kind: 'other'),
          event('two', [3]),
        ],
      ),
      bundle(
        events: [
          event('other', [1, 2]),
          event('two', [3]),
        ],
      ),
      bundle(
        events: [
          event('one', [1, 2], at: later),
          event('two', [3]),
        ],
      ),
      bundle(
        events: [
          event('two', [3]),
          event('one', [1, 2]),
        ],
      ),
    ];

    for (final variant in variants) {
      expect(variant, isNot(original));
    }
  });

  test('CommandBundle round trips with JSON', () {
    final original = bundle();
    final restored = CommandBundle.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored, original);
    expect(restored.hashCode, original.hashCode);
  });

  test('string representations include metadata without payload bytes', () {
    final original = bundle(
      events: [
        event('one', [0, 255]),
      ],
    );

    expect(original.toString(), contains('CommandBundle(commandId: CommandId'));
    expect(original.toString(), contains('events: [BundledEvent('));
    expect(original.events.single.toString(), contains('byteLength: 2'));
    expect(original.toString(), isNot(contains('AP8=')));
  });
}
