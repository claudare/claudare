import 'dart:typed_data';

/// A snapshot of a command's registered blob write.
class SavedBlob {
  final String blobId;
  final Uint8List data;

  SavedBlob(this.blobId, Uint8List data)
    : data = Uint8List.fromList(data).asUnmodifiableView();
}
