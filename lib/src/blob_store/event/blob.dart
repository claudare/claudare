import 'dart:convert';
import 'dart:typed_data';

import 'package:core/src/blob_store/blob_chunk_sizing.dart';
import 'package:core/src/blob_store/sodium_secretstream_xchacha20poly1305_const.dart';
import 'package:core/src/device_id.dart';

part 'blob_created.dart';
part 'blob_ready.dart';
part 'blob_tombstoned.dart';

sealed class BlobEvent {
  const BlobEvent();

  Map<String, dynamic> toJson();
}
