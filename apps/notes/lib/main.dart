import 'package:flutter/material.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/application/production_application_factory.dart';

import 'package:notes/screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final application = const ProductionApplicationFactory().create();

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
