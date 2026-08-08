import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

Future<String> getApplicationDirectory() async {
  final appDir = await getApplicationSupportDirectory();
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }

  return appDir.path;
}
