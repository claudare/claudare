import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/src/rpc_server/transport.dart';

class RpcServerTransportHttp extends RpcServerTransport {
  // final InternetAddress address;
  HttpServer? _server;

  RpcServerTransportHttp();

  @override
  int get port => _server?.port ?? 0;

  @override
  Future<void> stop() async {
    if (_server == null) {
      throw Exception('Server is already stopped');
    }

    await _server!.close(force: false);

    _server = null;
  }

  // internet address is always 0.0.0.0? port used is 80 here, always

  @override
  Future<void> start(Uri listenUri, RpcServerHandler handler) async {
    if (_server != null) {
      throw Exception('Server is already started');
    }

    // extracting the server params from the uri
    // http://0.0.0.0:54321/path
    final host = listenUri.host;
    final port = listenUri.port;
    final path = listenUri.path;
    // print('listen uri $listenUri. Host $host, port $port, path $path');

    final server = await HttpServer.bind(host, port);
    _server = server;

    server.listen(
      _requestHandler(path, handler),
      onError: (err) {
        print('unknown server error? $err');
      },
      onDone: () {
        // TODO: cleanup duties
      },
    );
  }

  void Function(HttpRequest) _requestHandler(
    String handlerPath,
    RpcServerHandler handler,
  ) {
    return (HttpRequest request) async {
      // check header type
      if (request.uri.path != handlerPath &&
          request.method != 'POST' &&
          request.headers.contentType !=
              ContentType('application', 'octet-stream')) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
        return;
      }

      try {
        final List<List<int>> chunks = [];
        await for (var chunk in request) {
          chunks.add(chunk);
        }

        // / Combine all chunks into a single Uint8List
        final int totalLength = chunks.fold(
          0,
          (sum, chunk) => sum + chunk.length,
        );
        final Uint8List fullData = Uint8List(totalLength);

        var offset = 0;
        for (var chunk in chunks) {
          fullData.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }

        final response = await handler(fullData);

        request.response
          ..headers.contentType = ContentType('application', 'octet-stream')
          ..add(response)
          ..close();
      } catch (e, stack) {
        print('error processing request: $e');
        print(stack);

        final debugErrorMsg = utf8.encode('$e; $stack');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..add(debugErrorMsg) // maybe send the error? (for debug purposes)
          ..close();
      }
    };
  }
}

void main() {
  HttpServer.bind(InternetAddress.loopbackIPv4, 8080).then((server) {
    print('Server listening on port 8080');
    server.listen((HttpRequest request) {
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response
          ..write('Hello, World!')
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  });
}
