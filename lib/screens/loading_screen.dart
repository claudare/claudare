import 'package:flutter/material.dart';
import 'package:notes_app_v0/application_provider.dart';
import 'package:notes_app_v0/screens/home_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  String _error = '';

  void _onError(dynamic error) {
    setState(() {
      _error = error.toString();
    });

    print('loading encountered an error: $error');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // final services = ServiceProvider.of(context);
    final application = ApplicationProvider.of(context);

    application
        .initialize()
        .then((_) {
          setState(() {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          });
        })
        .catchError((err) {
          _onError(err);
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) {
      return Scaffold(
        body: Center(child: Text(_error, style: TextStyle(color: Colors.red))),
      );
    }

    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Center(child: CircularProgressIndicator()), Text('loading')],
      ),
    );
  }
}
