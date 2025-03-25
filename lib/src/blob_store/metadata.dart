import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Metadata for the client side
/// Stored as the first part of the blob, encrypted with the rest of the data
/// this is immutable and will never change
class BlobMetadata {
  final int plaintextLengthBytes;
  final String mimeType;

  // this could also hold arbitrary key value pairs
  // or that is left upto the application to contruct own metadatas there
  // final List<{Key, Value}> extra;

  const BlobMetadata(this.plaintextLengthBytes, this.mimeType);

  factory BlobMetadata.fromJson(Map<String, dynamic> json) {
    return BlobMetadata(json['plaintextSizeBytes'], json['mimeType']);
  }

  Map<String, dynamic> toJson() => {
    'plaintextSizeBytes': plaintextLengthBytes,
    'mimeType': mimeType,
  };
}

/// [BlobStreamWithMetadata] packs and unpacks metadata from the decrypted stream
/// encryption is added to here?
class BlobStreamWithMetadata {
  final BlobMetadata metadata;

  /// actual file data here
  final Stream<List<int>> _underlyingStream;

  const BlobStreamWithMetadata(this.metadata, this._underlyingStream);

  Stream<List<int>> get content => _underlyingStream;

  /// Static function to write metadata and stream and return another stream
  static Stream<List<int>> wrapContent(
    BlobMetadata metadataEncrypted,
    Stream<List<int>> content,
  ) {
    late final StreamController<List<int>> controller;

    controller = StreamController<List<int>>(
      onListen: () async {
        try {
          final jsonEncoded = json.encode(metadataEncrypted.toJson());
          final utfied = utf8.encode('$jsonEncoded\n');

          // First send metadata
          controller.add(utfied);

          // Then pipe the stream with proper backpressure
          await for (final chunk in content) {
            if (controller.isClosed) break;
            await controller.addStream(Stream.value(chunk));
          }

          await controller.close();
        } catch (e, stack) {
          controller.addError(e, stack);
          await controller.close();
        }
      },
      onPause: () {
        content.listen(null).pause();
      },
      onResume: () {
        content.listen(null).resume();
      },
      onCancel: () {
        content.listen(null).cancel();
      },
    );

    return controller.stream;
  }

  static Stream<List<int>> wrapUint8List(
    BlobMetadata metadataEncrypted,
    Uint8List data,
  ) {
    return wrapContent(metadataEncrypted, Stream.value(data));
  }

  static Future<BlobStreamWithMetadata> fromRawStream(
    Stream<List<int>> rawStream,
  ) async {
    final metadataBytes = <int>[];
    final completer = Completer<BlobStreamWithMetadata>();

    final dataController = StreamController<List<int>>();
    bool foundNewline = false;

    final subscription = rawStream.listen(
      (data) {
        if (foundNewline) {
          // Already past metadata, just forward the data
          dataController.add(data);
          return;
        }

        for (int i = 0; i < data.length; i++) {
          if (data[i] == 0xA) {
            // ASCII newline was found
            foundNewline = true;

            metadataBytes.addAll(data.sublist(0, i));

            // Parse metadata
            final metadataJson = utf8.decode(metadataBytes);

            try {
              final metadata = BlobMetadata.fromJson(json.decode(metadataJson));

              // Add remaining data to the stream
              if (i + 1 < data.length) {
                dataController.add(data.sublist(i + 1));
              }

              completer.complete(
                BlobStreamWithMetadata(metadata, dataController.stream),
              );
              return;
            } catch (e) {
              completer.completeError(e);
              return;
            }
          }
        }

        // No newline in this chunk, add all to metadata buffer
        metadataBytes.addAll(data);
      },
      onDone: () {
        if (!foundNewline) {
          completer.completeError(
            FormatException('No newline found to separate metadata'),
          );
        }
        dataController.close();
      },
      onError: (e, st) {
        completer.completeError(e, st);
        dataController.close();
      },
      cancelOnError: true,
    );

    // Handle the case where the consumer cancels the stream
    dataController.onCancel = () {
      subscription.cancel();
    };

    return completer.future;
  }

  Future<Uint8List> readUint8List() async {
    final totalLength = metadata.plaintextLengthBytes;

    final data = Uint8List(totalLength);
    var offset = 0;

    await for (final chunk in _underlyingStream) {
      // this will throw if too much data is present...
      if (chunk.length > totalLength - offset) {
        throw Exception(
          'Size mismatch, overflow. Expected $totalLength, got ${offset + chunk.length}',
        );
      }
      data.setAll(offset, chunk);
      offset += chunk.length;
    }

    if (offset < totalLength) {
      throw Exception(
        "Size mismatch, nexpected end of stream. Expected $totalLength, got $offset",
      );
    }

    return data;
  }
}
