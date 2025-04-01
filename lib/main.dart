import 'package:flutter/material.dart';
import 'package:notes_app_v0/services.dart';
import 'package:notes_app_v0/init_page.dart';

void main() {
  // ensure services are initialized
  Services();
  runApp(const MyApp());
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
      home: const InitPage(),
    );
  }
}
