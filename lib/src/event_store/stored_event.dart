import 'package:core/src/event_store/id.dart';

class StoredEvent {
  final EventId id;
  final String data; // this must be string, as json does not allow binaries

  StoredEvent(this.id, this.data);

  StoredEvent.fromJson(Map<String, dynamic> json)
    : id = EventId.fromString(json['id']),
      data = json['data'];

  Map<String, dynamic> toJson() => {'id': id.toString(), 'data': data};
}
