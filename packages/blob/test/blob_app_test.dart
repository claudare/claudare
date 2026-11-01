import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';

void main() {
  late CqrsTestRuntime runtime;
  late BlobApp app;

  setUp(() {
    runtime = CqrsTestRuntime();
    app = BlobApp(
      runtime: runtime,
      blobStore: MemoryBlobStore(),
      idGenerator: IdGeneratorStatic('blob-id'),
    );
  });

  test('saves and retrieves bytes using the generated ID', () async {
    final command = _SaveBlob(app, Uint8List.fromList([1, 2]));

    await runtime.execute(command);

    expect(command.id, 'blob-id');
    expect(await app.get(command.id), [1, 2]);
  });

  test('creates an event on the blob stream', () async {
    await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));

    final events = await runtime.streamReader('_blob/blob-id').scan().toList();
    expect(events, hasLength(1));
    expect(
      runtime.eventRegistry.decode<Object>(events.single.encodedEvent),
      isA<BlobCreated>(),
    );
  });
}

final class _SaveBlob implements Command {
  final BlobApp app;
  final Uint8List data;
  late String id;

  _SaveBlob(this.app, this.data);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    id = await app.save(ctx, data);
  }
}
