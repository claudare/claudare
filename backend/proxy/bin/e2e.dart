import 'dart:async';
import 'dart:convert';
import 'dart:io';

// This development tester intentionally uses dev dependencies from bin.
// ignore: depend_on_referenced_packages
import 'package:claudare_logging/claudare_logging.dart';
import 'package:proxy/proxy.dart';
// ignore: depend_on_referenced_packages
import 'package:web_socket_channel/io.dart';

Future<void> main() async {
  final baseUrl = Uri.parse(
    'ws://localhost:${Platform.environment['PORT'] ?? '7000'}/',
  );
  final logger = ConsoleLogger(name: 'proxy.e2e', minimumLevel: LogLevel.info);
  try {
    logger.info('Connecting to $baseUrl');
    await Future.wait([
      runClient(baseUrl, 'a', 'b', 'Wazzap B', logger),
      runClient(baseUrl, 'b', 'a', 'Nothin', logger),
    ]);
  } finally {
    await logger.close();
  }
}

Future<void> runClient(
  Uri baseUrl,
  String thisActor,
  String peerActor,
  String data,
  Logger logger,
) async {
  final channel = IOWebSocketChannel.connect(
    baseUrl,
    headers: ProxyInit(actor: thisActor, group: 'test').toHeaders(),
  );
  Timer? timer;
  try {
    await channel.ready;
    logger.info('[$thisActor] connected');
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      channel.sink.add(
        jsonEncode(ProxyDirectMessage(actor: peerActor, data: data).toJson()),
      );
    });
    await for (final message in channel.stream) {
      final decoded = ProxyMessage.fromJson(
        jsonDecode(message as String) as Map<String, dynamic>,
      );
      switch (decoded) {
        case ProxyDirectMessage(:final actor):
          logger.info('[$thisActor] received message from $actor');
        case ProxyBroadcastMessage():
          throw UnimplementedError('Group messages are not implemented');
      }
    }
  } finally {
    timer?.cancel();
    await channel.sink.close();
    logger.info('[$thisActor] disconnected');
  }
}
