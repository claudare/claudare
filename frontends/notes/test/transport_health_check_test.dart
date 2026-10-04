import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/screens/settings/transport_health_check.dart';

void main() {
  final url = Uri.parse('http://server.test:7000/health');

  for (final status in [200, 204, 299, 301, 404, 500]) {
    test('health HTTP status $status', () async {
      final client = _Client(() async => _Response(status));
      final check = TransportHealthCheck(createClient: () => client);

      expect(await check(url), status >= 200 && status < 300);
      expect(client.requested, url);
      expect(client.forceClosed, isTrue);
    });
  }

  test('network failure closes the client', () async {
    final client = _Client(
      () async => throw const SocketException('unavailable'),
    );
    final check = TransportHealthCheck(createClient: () => client);

    expect(await check(url), isFalse);
    expect(client.forceClosed, isTrue);
  });

  test('request timeout closes the client and ignores late response', () async {
    final pending = Completer<HttpClientResponse>();
    final client = _Client(() => pending.future);
    final check = TransportHealthCheck(
      createClient: () => client,
      timeout: const Duration(milliseconds: 1),
    );

    expect(await check(url), isFalse);
    expect(client.forceClosed, isTrue);
    pending.complete(_Response(200));
  });
}

class _Client implements HttpClient {
  final Future<HttpClientResponse> Function() respond;
  Uri? requested;
  bool forceClosed = false;

  _Client(this.respond);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    return _Request(respond);
  }

  @override
  void close({bool force = false}) => forceClosed = force;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  final Future<HttpClientResponse> Function() respond;

  _Request(this.respond);

  @override
  Future<HttpClientResponse> close() => respond();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response implements HttpClientResponse {
  @override
  final int statusCode;

  _Response(this.statusCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
