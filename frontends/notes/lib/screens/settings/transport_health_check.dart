import 'dart:async';
import 'dart:io';

/// Checks HTTP availability without opening a transport connection.
class TransportHealthCheck {
  final Duration timeout;
  final HttpClient Function() _createClient;

  TransportHealthCheck({
    this.timeout = const Duration(seconds: 10),
    HttpClient Function()? createClient,
  }) : _createClient = createClient ?? HttpClient.new;

  /// Returns whether [url] responds with a successful HTTP status.
  Future<bool> call(Uri url) async {
    final client = _createClient();
    try {
      return await (() async {
        final request = await client.getUrl(url);
        final response = await request.close();
        return response.statusCode >= 200 && response.statusCode < 300;
      })().timeout(timeout);
    } on Exception {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
