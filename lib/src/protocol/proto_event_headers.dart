import 'package:core/src/device_id.dart';
import 'package:messagepack/messagepack.dart';

sealed class ProtoEventAnyHeader {
  const ProtoEventAnyHeader();

  void pack(Packer p);
  ProtoEventAnyHeader.unpack(Unpacker u);

  static final Map<int, ProtoEventAnyHeader Function(Unpacker)> _unpackers = {
    ProtoEventHeaderAuth._type: (u) => ProtoEventHeaderAuth.unpack(u),
    ProtoEventHeaderAckAsk._type: ProtoEventHeaderAckAsk.unpack,
    ProtoEventHeaderAckOk._type: ProtoEventHeaderAckOk.unpack,
    ProtoEventHeaderAckError._type: ProtoEventHeaderAckError.unpack,
  };

  static ProtoEventAnyHeader anyUnpack(Unpacker u) {
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

class ProtoEventHeaderEmpty extends ProtoEventAnyHeader {
  // static const _type = 0;

  const ProtoEventHeaderEmpty();

  @override
  void pack(Packer p) {
    throw Exception("empty header is not packable");
  }
}

/// [ProtoEventHeaderAuth] provides a way for devices to authenticate with each
/// other. For now, they siply send their DeviceId and it is trusted
class ProtoEventHeaderAuth extends ProtoEventAnyHeader {
  static const _type = 1; // unique index to each one

  final DeviceId deviceId;

  const ProtoEventHeaderAuth(this.deviceId);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(deviceId.value);
  }

  factory ProtoEventHeaderAuth.unpack(Unpacker p) {
    final deviceInt = p.unpackInt();
    return ProtoEventHeaderAuth(DeviceId(deviceInt!));
  }
}

/// [ProtoEventHeaderAckAsk] requests the responder to confirm on this whole
/// payload. Possible answers come in later in headers as
/// [ProtoEventHeaderAckOk] and [ProtoEventHeaderAckError]
class ProtoEventHeaderAckAsk extends ProtoEventAnyHeader {
  static const _type = 10;

  final int payloadId;

  const ProtoEventHeaderAckAsk(this.payloadId);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(payloadId);
  }

  factory ProtoEventHeaderAckAsk.unpack(Unpacker p) {
    final payloadId = p.unpackInt();
    return ProtoEventHeaderAckAsk(payloadId!);
  }
}

class ProtoEventHeaderAckOk extends ProtoEventAnyHeader {
  static const _type = 11;

  final int payloadId;

  const ProtoEventHeaderAckOk(this.payloadId);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(payloadId);
  }

  factory ProtoEventHeaderAckOk.unpack(Unpacker p) {
    final payloadId = p.unpackInt();
    return ProtoEventHeaderAckOk(payloadId!);
  }
}

class ProtoEventHeaderAckError extends ProtoEventAnyHeader {
  static const _type = 12;

  final int payloadId;
  // string is used for now
  final String message;

  const ProtoEventHeaderAckError(this.payloadId, this.message);

  @override
  void pack(Packer p) {
    // cheat for now and dont use the packing methods on the DeviceId
    p.packInt(_type);
    p.packInt(payloadId);
    p.packString(message);
  }

  factory ProtoEventHeaderAckError.unpack(Unpacker p) {
    final payloadId = p.unpackInt()!;
    final message = p.unpackString()!;
    return ProtoEventHeaderAckError(payloadId, message);
  }
}
