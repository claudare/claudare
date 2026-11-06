# Blob

Provides local blob storage.

## Example

```dart
final blobs = BlobApp(runtime: runtime, blobStore: MemoryBlobStore());

// Create a blob inside a command handler:
final id = await blobs.save(ctx, bytes);
final saved = await blobs.get(id);

// Delete a blob in a command handler:
await blobs.delete(ctx, id);

// While the runtime is idle:
await blobs.optimize();
```
