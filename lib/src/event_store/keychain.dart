import 'package:core/core.dart';
import 'package:core/src/encryption/aes256.dart';

class EventKeychainValue {
  final EncryptionKeyAes256 key;

  /// Inclusive value. The key starts from this event time
  final Timestamp from;

  /// Exclusive value. At this event time, use next key
  /// If null, this key is still valid
  final Timestamp? to;

  const EventKeychainValue(this.key, this.from, this.to);
}

/// [EventKeychain] stores SYMMERTIC encryption keys for each device and
/// event-time range. Would be nice to make this use generic keys (the same was
/// as in encryption sub-package), but for now its hardcoded to unverified
/// AES256 implementation.
class EventKeychain {
  final Map<DeviceId, List<EventKeychainValue>> _map;

  const EventKeychain(this._map);
}
