import 'package:flutter/material.dart';
import 'package:notes/application/application_provider.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/command/update_note_content.dart';
import 'package:notes/command/update_note_title.dart';
import 'package:notes/screens/error_screen.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/util/get_application_directory.dart';
import 'package:path/path.dart' as path;

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  // progress state goes in here

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final application = ApplicationProvider.of(context);
    application.logger.debug('LoadingScreen didChangeDependencies');

    _initApplication();
  }

  Future<void> _initApplication() async {
    final application = ApplicationProvider.of(context);

    try {
      final baseDir = await getApplicationDirectory();
      await application.initialize(
        notesDbFilepath: path.join(baseDir, 'notes.db'),
        searchDbFilepath: path.join(baseDir, 'search.db'),
      );

      // FIXME: error handling is missing pre-rework
      // The application should go to an error state
      // application.setFatalErrorHandler((error) {
      //   application.logger.error(
      //     'FATAL ERROR WAS DETETCED. error: $error, isMounted: $mounted',
      //     error,
      //   );

      //   if (!mounted) return;
      //   navigateToErrorScreen(context, error.toString());
      // });

      try {
        await application.commandExecute(
          const CreateNote(),
          CreateNoteInput(noteId: 'test'),
        );
        await application.commandExecute(
          const UpdateNoteTitle(),
          UpdateNoteTitleInput(noteId: 'test', fullValue: 'first note'),
        );
        await application.commandExecute(
          const UpdateNoteContent(),
          UpdateNoteContentInput(
            noteId: 'test',
            overrideContent:
                'this is an example note data inserted at the intialization. Application development on track! :)',
          ),
        );
      } on Exception {
        application.logger.debug('test data was not inserted');
      }

      if (!mounted) {
        throw Exception('not mounted after loading');
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(application: application),
        ),
      );
    } on Exception catch (error, stackTrace) {
      if (!mounted) return;
      application.logger.error(
        'error in initialization: $error',
        error,
        stackTrace,
      );
      navigateToErrorScreen(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: CircularProgressIndicator());

    // return Scaffold(
    //   body: Column(
    //     mainAxisAlignment: MainAxisAlignment.center,
    //     children: [Center(child: CircularProgressIndicator()), Text('loading')],
    //   ),
    // );
  }
}
