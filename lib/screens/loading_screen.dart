import 'package:flutter/material.dart';
import 'package:notes_app_v0/application/application_provider.dart';
import 'package:notes_app_v0/command/create_note.dart';
import 'package:notes_app_v0/command/update_note_content.dart';
import 'package:notes_app_v0/command/update_note_title.dart';
import 'package:notes_app_v0/screens/error_screen.dart';
import 'package:notes_app_v0/screens/home/home_screen.dart';
import 'package:notes_app_v0/util/get_application_directory.dart';

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

    print('LoadingScreen didChangeDependencies');

    _initApplication();
  }

  Future<void> _initApplication() async {
    final application = ApplicationProvider.of(context);

    try {
      final baseDir = await getApplicationDirectory();
      await application.initialize(baseDir);

      // TODO: implement proper error handling:
      // https://docs.flutter.dev/testing/errors#handling-all-types-of-errors
      // This will only work if there is an issue during initialization
      application.notesRuntime.setFatalErrorHandler((error) {
        print('FATAL ERROR WAS DETETCED. error: $error, isMounted: $mounted');

        // TODO: the mount does not exist after navigation
        if (!mounted) return;
        navigateToErrorScreen(context, error.toString());
      });

      try {
        await application.notesRuntime.commands.createNote.runThrowable(
          CreateNoteInput(noteId: 'test'),
        );
        await application.notesRuntime.commands.updateNoteTitle.runThrowable(
          UpdateNoteTitleInput(noteId: 'test', fullValue: 'first note'),
        );
        await application.notesRuntime.commands.updateNoteContent.runThrowable(
          UpdateNoteContentInput(
            noteId: 'test',
            overrideContent:
                'this is an example note data inserted at the intialization. Application development on track! :)',
          ),
        );
      } catch (_) {
        print('test data was not inserted');
      }

      if (!mounted) {
        throw Exception('not mounted after loading');
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (context) => HomeScreen(notesRuntime: application.notesRuntime),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      print('error in initialization: $e');
      navigateToErrorScreen(context, e.toString());
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
