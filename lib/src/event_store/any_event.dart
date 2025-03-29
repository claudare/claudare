import 'dart:typed_data';

import 'package:core/src/event_store/id.dart';

abstract class AnyEvent {
  // toJson, fromJson
  Map<String, dynamic> toJson();
  AnyEvent.fromJson(Map<String, dynamic> json);
}

class StoredEvent {
  final EventId id;
  final Uint8List data;

  StoredEvent(this.id, this.data);
}
