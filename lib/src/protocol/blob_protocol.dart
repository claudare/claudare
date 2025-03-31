// import 'package:core/src/blob_store/id.dart';

// blob streaming is totally different protocol, as it uses a different connection
// usually served by a "different" server

// streaming is done via chunked transfer...
// No reliance on any existing protocol like http, please :)
// for now http chunked-transfer will be used, as implenting
// this properly is hard.

sealed class BlobAnyMessage {
  const BlobAnyMessage();
}

// // [MessageBlobChunkedInit] will initiate the stream by providing base information
// class BlobMessageChunkedInit extends BlobAnyMessage {
//   final BlobId blobId;
//   final int transferId;
//   final int chunkCount;
//   final int totalSizeBytes;
//   final int chunkSizeBytes;
// }

// class BlobMessageChunk extends BlobAnyMessage {
//   final int transferId;
//   final int chunkId;
//   final int chunkSizeBytes;
//   final Uint8List data;
// }

// /// [BlobMessageComplete] will single chunk send data, useful for small blobs
// class BlobMessageComplete extends BlobAnyMessage {
//   final BlobId blobId;
//   final int transferId;
//   final int totalSizeBytes;
//   final Uint8List data;
// }
