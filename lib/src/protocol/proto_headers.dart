import 'package:core/device_keychain.dart';
import 'package:core/src/device_id.dart';
import 'package:messagepack/messagepack.dart';

// would be nice to use an enum, but its a pain dart :)
// enum ProtoAnyHeaderType {
//   auth(0),
//   ack(10);

//   final int value;

//   const ProtoAnyHeaderType(this.value);
// }

sealed class ProtoAnyHeader {
  const ProtoAnyHeader();

  void pack(Packer p);
  int get type;

  static const Map<int, ProtoAnyHeader Function(Unpacker)> _unpackers = {
    ProtoHeaderAuth.staticType: ProtoHeaderAuth.unpack,
    ProtoHeaderAck.staticType: ProtoHeaderAck.unpack,
    ProtoHeaderForward.staticType: ProtoHeaderForward.unpack,
  };

  static ProtoAnyHeader unpack(Unpacker u) {
    final type = u.unpackInt();

    if (type == null || type == 0) {
      throw Exception('Bad packed type field: $type');
    }
    if (!_unpackers.containsKey(type)) {
      throw Exception('Unknown message type: $type');
    }

    return _unpackers[type]!(u);
  }
}

/// [ProtoHeaderAuth] provides a way for devices to authenticate with each
/// other. For now, they siply send their DeviceId and it is trusted
class ProtoHeaderAuth extends ProtoAnyHeader {
  static const staticType = 1; // unique index to each one

  final DeviceClaim claim;

  const ProtoHeaderAuth(this.claim);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    claim.pack(p);
  }

  factory ProtoHeaderAuth.unpack(Unpacker u) {
    final claim = DeviceClaim.unpack(u);
    return ProtoHeaderAuth(claim);
  }
}

/// [ProtoHeaderAck] requests the responder to confirm on this whole
/// payload. Ack is sent with the same id back to conform deny. Optional
/// error can be attached, throwing the requester.
class ProtoHeaderAck extends ProtoAnyHeader {
  static const staticType = 10;

  final int payloadId;
  final String error;

  const ProtoHeaderAck(this.payloadId, this.error);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(staticType);
    p.packInt(payloadId);
    p.packString(error.isEmpty ? null : error);
  }

  factory ProtoHeaderAck.unpack(Unpacker p) {
    final payloadId = p.unpackInt();
    final error = p.unpackString() ?? "";
    return ProtoHeaderAck(payloadId!, error);
  }
}

/// [ProtoHeaderForward] specifies that the content of this payload must be
/// proxied to another device. Works in conjunction with [ProtoMessageForwardData]
class ProtoHeaderForward extends ProtoAnyHeader {
  static const staticType = 11;

  final DeviceId deviceId;

  const ProtoHeaderForward(this.deviceId);

  @override
  int get type => staticType;

  @override
  void pack(Packer p) {
    p.packInt(staticType);
    deviceId.pack(p);
  }

  factory ProtoHeaderForward.unpack(Unpacker u) {
    final deviceId = DeviceId.unpack(u);
    return ProtoHeaderForward(deviceId);
  }
}
