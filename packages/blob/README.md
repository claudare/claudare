# Blob

Provides immutable blob storage and an index of local blob availability.

Use `BlobStore` to write and save blobs.

```dart
final blobs = BlobStore(index: MemoryBlobIndex(), storage: MemoryBlobStorage());
await blobs.save('blob-id', bytes);
final saved = await blobs.get('blob-id');
```
