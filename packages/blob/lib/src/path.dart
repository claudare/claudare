const _blobPrefix = '_blob/';

String blobIdFromStream(String path) {
  if (!path.startsWith(_blobPrefix) || path.length == _blobPrefix.length) {
    throw const FormatException('Invalid blob stream path');
  }

  return path.substring(_blobPrefix.length);
}

String blobStream(String blobId) => '$_blobPrefix$blobId';
