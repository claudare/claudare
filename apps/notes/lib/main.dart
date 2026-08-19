import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/material.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/screens/loading_screen.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final application = NoteApplication(
    idGenerator: IdGeneratorSecure(),
    timeProvider: SystemTimeProvider(),
    logger: ConsoleLogger(name: 'notes', minimumLevel: LogLevel.debug),
  );

  runApp(
    NoteApplicationProvider(application: application, child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home: const LoadingScreen(),
    );
  }
}
