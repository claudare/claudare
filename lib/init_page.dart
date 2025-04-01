import 'package:flutter/material.dart';
import 'package:notes_app_v0/controller_provider.dart';
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

  void _onError(dynamic error) {
    setState(() {
      _error = error.toString();
    });

    throw error;
  }

  // this must only be ran once
  // TODO: if something breaks here, thats because of dependency changes...
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // final services = ServiceProvider.of(context);
    final controller = ControllerProvider.of(context);

    controller
        .initPersisted()
        // .initTemporary()
        .then((_) {
          controller
              .loadRepo()
              .then((_) {
                setState(() {
                  _initialized = true;

                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const NoteListPage(),
                    ),
                  );
                });
              })
              .catchError((err) {
                _onError(err);
              });
        })
        .catchError((err) {
          _onError(err);
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
