import 'package:core/src/device_id.dart';
import 'package:messagepack/messagepack.dart';

sealed class ProtoAnyHeader {
  const ProtoAnyHeader();

  void pack(Packer p);
  // ProtoAnyHeader.unpack(Unpacker u);

  static const Map<int, ProtoAnyHeader Function(Unpacker)> _unpackers = {
    ProtoHeaderAuth._type: ProtoHeaderAuth.unpack,
    ProtoHeaderAckAsk._type: ProtoHeaderAckAsk.unpack,
    ProtoHeaderAckOk._type: ProtoHeaderAckOk.unpack,
    ProtoHeaderAckError._type: ProtoHeaderAckError.unpack,
  };

  static ProtoAnyHeader unpack(Unpacker u) {
    final type = u.unpackInt();

    if (type == null || type == 0) {
      throw Exception('bad packed type field: $type');
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
  static const _type = 1; // unique index to each one

  final DeviceId deviceId;

  const ProtoHeaderAuth(this.deviceId);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(deviceId.value);
  }

  factory ProtoHeaderAuth.unpack(Unpacker p) {
    final deviceInt = p.unpackInt();
    return ProtoHeaderAuth(DeviceId(deviceInt!));
  }
}

/// [ProtoHeaderAckAsk] requests the responder to confirm on this whole
/// payload. Possible answers come in later in headers as
/// [ProtoHeaderAckOk] and [ProtoHeaderAckError]
class ProtoHeaderAckAsk extends ProtoAnyHeader {
  static const _type = 10;

  final int payloadId;

  const ProtoHeaderAckAsk(this.payloadId);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(payloadId);
  }

  factory ProtoHeaderAckAsk.unpack(Unpacker p) {
    final payloadId = p.unpackInt();
    return ProtoHeaderAckAsk(payloadId!);
  }
}

class ProtoHeaderAckOk extends ProtoAnyHeader {
  static const _type = 11;

  final int payloadId;

  const ProtoHeaderAckOk(this.payloadId);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(payloadId);
  }

  factory ProtoHeaderAckOk.unpack(Unpacker p) {
    final payloadId = p.unpackInt();
    return ProtoHeaderAckOk(payloadId!);
  }
}

class ProtoHeaderAckError extends ProtoAnyHeader {
  static const _type = 12;

  final int payloadId;
  // string is used for now
  final String message;

  const ProtoHeaderAckError(this.payloadId, this.message);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(payloadId);
    p.packString(message);
  }

  factory ProtoHeaderAckError.unpack(Unpacker p) {
    final payloadId = p.unpackInt()!;
    final message = p.unpackString()!;
    return ProtoHeaderAckError(payloadId, message);
  }
}
