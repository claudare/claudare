# event store

## Implementation details

This is not up-to date. Really struggling with no device-local database

```sql
CREATE TABLE event(
  local_device_app_sequence INTEGER AUTOINCREMENT, -- autoincremented sequence number for the current app_instance (aka device, app combo)
  app_id STRING, -- in which application the event was emitted
  app_sequence INTEGER, 
  app_device_sequence INTEGER,
  stream_id STRING, -- stream id
  stream_version INTEGER, -- version of event within the stream
  kind STRING, -- event data
  detail STRING, -- event data
  occured_at INTEGER, -- event metadata
  device_id INTEGER, -- which device issued the event
  device_sequence INTEGER,
  causal_sequence INTEGER
);
```

```dart
// schema is the following:
// app_id for multi-app tenancy
// (app_id, stream_id, stream_version) for local consistency checks
// (app_id, device_id, causal_sequence) for sync, event dependency tracking
// (app_id, device_id, device_sequence) for sync, events are downloaded sequentially
// (local_sequence) for fully offline isolated app projection catchup and playback
// local sequence as an app sequence
// but the blob access of `$blob` app needs to be resolved locally!!!
// so each app will hold all blob events? sure.
// device enrollment? okay.
// app enrollment? of course.
// calendar common? yes.
// only 3 special apps like that
```
