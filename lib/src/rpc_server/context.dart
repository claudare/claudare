import 'package:core/device_keychain.dart';
import 'package:core/src/blob_store/store.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/store.dart';

class ServerContext {
  final DeviceKeychain deviceKeychain;

  final EventStore eventStore;
  final BlobStore blobStore;
  // this needs to have access to network send/recieve primitives

  const ServerContext(this.deviceKeychain, this.eventStore, this.blobStore);
}

class RequestContext {
  DeviceId deviceId;

  RequestContext(this.deviceId);
}
