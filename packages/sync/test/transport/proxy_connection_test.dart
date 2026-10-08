import 'dart:async';
import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:id_generator/id_generator.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  test(
    'failed default connection reports failure without waiting for a channel',
    () async {
      final client = _Client();
      final transport = _transport(client);
      final starting = transport.start();
      final failed = expectLater(starting, throwsA(isA<HttpException>()));
      client.request.completeError(const HttpException('offline'));
      await failed.timeout(const Duration(seconds: 1));
      expect(client.forcedClose, isTrue);
    },
  );

  test('closing aborts the default pending HTTP connection', () async {
    final client = _Client();
    final transport = _transport(client);
    final starting = transport.start();
    final failed = expectLater(starting, throwsA(isA<HttpException>()));
    await transport.close().timeout(const Duration(seconds: 1));
    expect(client.forcedClose, isTrue);
    await failed.timeout(const Duration(seconds: 1));
  });
}

WebSocketProxyTransport _transport(_Client client) {
  final transport = WebSocketProxyTransport(
    baseUrl: 'ws://unused',
    thisActor: 'local',
    group: 'notes',
    logger: const NoopLogger(),
    idGenerator: IdGeneratorRandom(),
    timeProvider: FakeTimeProviderStatic.zero(),
    createHttpClient: () => client,
  );
  final subscription = transport.peerTransports.listen((_) {});
  addTearDown(subscription.cancel);
  addTearDown(transport.close);
  return transport;
}

class _Client implements HttpClient {
  final request = Completer<HttpClientRequest>();
  bool forcedClose = false;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => request.future;

  @override
  void close({bool force = false}) {
    forcedClose = force;
    if (!request.isCompleted) {
      request.completeError(const HttpException('connection aborted'));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
