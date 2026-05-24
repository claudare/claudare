import 'package:flutter/material.dart';
import 'package:notes_app_v0/application/application_provider.dart';
import 'package:notes_app_v0/application/production_application_factory.dart';

import 'package:notes_app_v0/screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final application = ProductionApplicationFactory().create();

  runApp(ApplicationProvider(application: application, child: const MyApp()));
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
