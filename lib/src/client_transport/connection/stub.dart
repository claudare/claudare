import 'dart:async';
import 'dart:typed_data';

import 'package:core/src/net_connection.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:core/src/protocol/proto_payload.dart';

class NetConnectionStub extends NetConnection {
  /// values that were sent OUT to the sink by the code writing to the other peer
  final List<Uint8List> exgresValuesBytes = [];

  /// values that were sent IN from imaginary peer (test pushing values)
  final List<Uint8List> ingresValuesBytes = [];
  late StreamController<Uint8List> _inputController;
  late StreamController<Uint8List> _outputController;

  bool isConnected = false;

  NetConnectionStub() {
    _inputController = StreamController<Uint8List>.broadcast();
    _outputController = StreamController<Uint8List>.broadcast();
    _outputController.stream.listen((data) {
      exgresValuesBytes.add(data);
    });
  }

  @override
  StreamSink<Uint8List> get sink => _outputController.sink;

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  Future<void> connect(Uri endpoint) async {
    // Simulate connection, nothing is stubbed yet
    // in future can do failing connections
    isConnected = true;
  }

  // duplicates are okay in the stub
  @override
  Future<void> disconnect() async {
    // await _outputSubscription?.cancel();
    await _inputController.close();
    await _outputController.close();
    isConnected = false;
  }

  void add(Uint8List value) {
    ingresValuesBytes.add(value);
    _inputController.add(value);
  }

  // helpers
  int lastPayloadId = 0;

  void addPayloadMessage(ProtoAnyMessage message) {
    final payloadId = lastPayloadId++;
    add(ProtoPayload(payloadId, message).toBytes());
  }

  Function() onPayload(Function(ProtoPayload) fn) {
    final sub = _outputController.stream.listen((data) {
      final payload = ProtoPayload.fromBytes(data);
      fn(payload);
    });

    return () {
      sub.cancel();
    };
  }

  /// values that were sent OUT to the sink by the code writing to another peer
  List<ProtoPayload> get exgresValuesPayload =>
      exgresValuesBytes.map((bytes) => ProtoPayload.fromBytes(bytes)).toList();

  /// values that were sent IN from imaginary peer (test pushing values)
  List<ProtoPayload> get ingresValuesPayload =>
      ingresValuesBytes.map((bytes) => ProtoPayload.fromBytes(bytes)).toList();
}
