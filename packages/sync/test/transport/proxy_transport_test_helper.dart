import 'dart:async';
import 'dart:convert';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:id_generator/id_generator.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:time_provider/time_provider.dart';

class TestClock implements TimeProvider {
  DateTime _now = DateTime.utc(2026);
  final _timers = <TestTimer>[];

  @override
  DateTime now() => _now;

  Timer schedule(Duration delay, void Function() callback) {
    final timer = TestTimer(_now.add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  int get activeTimers => _timers.where((timer) => timer.isActive).length;

  Future<void> elapse(Duration duration) async {
    final target = _now.add(duration);
    while (true) {
      _timers.removeWhere((timer) => !timer.isActive);
      _timers.sort((a, b) => a.at.compareTo(b.at));
      if (_timers.isEmpty || _timers.first.at.isAfter(target)) break;
      final timer = _timers.removeAt(0);
      _now = timer.at;
      timer.fire();
      await flushMessages();
    }
    _now = target;
    await flushMessages();
  }
}

class TestTimer implements Timer {
  final DateTime at;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  TestTimer(this.at, this.callback);

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

typedef SentMessage = ({
  String sender,
  String target,
  TransportMessage message,
});

class TestProxy {
  final connections = <String, StreamChannel<Object?>>{};
  final groups = <String, String>{};
  final sent = <SentMessage>[];
  bool Function(SentMessage)? drop;

  Future<StreamChannel<Object?>> open(
    String url,
    Map<String, String> headers,
  ) async {
    final init = ProxyInit.fromHeaders(headers);
    final controller = StreamChannelController<Object?>();
    final server = controller.foreign;
    connections[init.actor] = server;
    groups[init.actor] = init.group;
    server.stream.listen(
      (frame) {
        final envelope = ProxyMessage.fromJson(
          jsonDecode(frame as String) as Map<String, dynamic>,
        );
        final message = TransportMessage.fromJson(
          jsonDecode(envelope.data) as Map<String, dynamic>,
        );
        final sentMessage = (
          sender: init.actor,
          target: envelope.actor,
          message: message,
        );
        sent.add(sentMessage);
        if (drop?.call(sentMessage) ?? false) return;
        final rewritten = jsonEncode(
          ProxyMessage(
            type: envelope.type,
            actor: init.actor,
            data: envelope.data,
          ).toJson(),
        );
        if (envelope.type == ProxyMessageType.direct) {
          connections[envelope.actor]?.sink.add(rewritten);
        } else {
          for (final entry in connections.entries) {
            if (groups[entry.key] == init.group) {
              entry.value.sink.add(rewritten);
            }
          }
        }
      },
      onDone: () {
        if (identical(connections[init.actor], server)) {
          connections.remove(init.actor);
          groups.remove(init.actor);
        }
      },
    );
    return controller.local;
  }

  void inject(String target, String sender, TransportMessage message) {
    injectRaw(
      target,
      jsonEncode(
        ProxyMessage(
          type: ProxyMessageType.direct,
          actor: sender,
          data: jsonEncode(message.toJson()),
        ).toJson(),
      ),
    );
  }

  void injectRaw(String target, Object? frame) =>
      connections[target]!.sink.add(frame);
}

class TestTransport {
  final peers = <PeerTransport>[];
  final errors = <Object>[];
  final finished = Completer<void>();
  late final WebSocketProxyTransport transport;
  void Function(PeerTransport)? onPeer;

  TestTransport(
    TestProxy proxy,
    TestClock clock,
    String actor, {
    String group = 'test',
    ProxyConnectionOpener? open,
    Logger logger = const NoopLogger(),
  }) {
    transport = WebSocketProxyTransport(
      baseUrl: 'ws://unused',
      thisActor: actor,
      group: group,
      logger: logger,
      idGenerator: TestIds(actor),
      timeProvider: clock,
      openConnection: open ?? proxy.open,
      timerFactory: clock.schedule,
    );
    transport.peerTransports.listen(
      (peer) {
        peers.add(peer);
        onPeer?.call(peer);
      },
      onError: errors.add,
      onDone: finished.complete,
    );
  }

  Future<void> start() => transport.start();
  Future<void> close() => transport.close();
}

class TestIds implements IdGenerator {
  final String actor;
  int _sequence = 0;
  TestIds(this.actor);

  @override
  String generateId() => '$actor-${++_sequence}';
}

Future<void> flushMessages() => Future<void>.delayed(Duration.zero);
