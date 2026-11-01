# Blob

Provides local blob storage.

Create a `BlobApp` with your CQRS runtime:

```dart
final blobs = BlobApp(runtime: runtime, blobStore: MemoryBlobStore());

// Inside a command handler:
final id = await blobs.save(ctx, bytes);
final saved = await blobs.get(id);
```
