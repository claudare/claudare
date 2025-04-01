import 'package:flutter/material.dart';
import 'package:notes_app_v0/service_provider.dart';
import 'package:notes_app_v0/note_list_page.dart';

// this will show the loading screen while the appplication is initializing
class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  String _error = '';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final services = ServiceProvider.of(context);

    services.repo
        .initFromDisk()
        .then((_) {
          setState(() {
            _initialized = true;

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const NoteListPage()),
            );
          });
        })
        .catchError((err) {
          setState(() {
            _error = err.toString();
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized) {
      return Text('done!');
    } else if (_error.isNotEmpty) {
      return Text('fatal error $_error', style: TextStyle(color: Colors.red));
    } else {
      return Center(
        child: Column(
          children: [CircularProgressIndicator(), Text('Loading...')],
        ),
      );
    }
  }
}
