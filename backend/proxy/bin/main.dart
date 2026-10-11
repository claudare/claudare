import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:proxy/proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

void main() async {
  final level = Platform.environment['LOG_LEVEL'] ?? 'debug';
  final logger = ConsoleLogger(
    name: 'proxy',
    minimumLevel: LogLevel.values.byName(level),
  );
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(
        logRequests(
          logger: (message, isError) {
            if (isError) {
              logger.error(message);
            } else {
              logger.debug(message);
            }
          },
        ),
      )
      .addHandler(createRouter(logger: logger).call);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '7000');
  final server = await serve(handler, ip, port);
  logger.info('Proxy server listening on port ${server.port}');
}
