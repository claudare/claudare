import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:notes_app_v0/controller.dart';
import 'package:notes_app_v0/controller_provider.dart';
import 'package:notes_app_v0/init_page.dart';

void main() {
  // the controller should load the device id
  final deviceId = DeviceId(0);

  runApp(
    ControllerProvider(controller: Controller(deviceId), child: const MyApp()),
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
      home: const InitPage(),
    );
  }
}
