import 'package:flutter/material.dart';
import 'package:notes_app_v0/common.dart';
import 'package:notes_app_v0/note_model.dart';
import 'package:notes_app_v0/note_widget.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // Hardcoded list of NoteModel instances for demonstration
    List<NoteModel> notes = [
      NoteModel(Id("1"), title: "First Note", body: "This is the first note."),
      NoteModel(
        Id("2"),
        title: "Second Note",
        body: "This is the second note.",
      ),
      NoteModel(Id("3"), title: "Third Note", body: "This is the third note."),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          // mainAxisAlignment: MainAxisAlignment.center,
          children:
              notes.map((note) => NoteStatefulWidget(note: note)).toList(),
        ),
      ),
    );
  }
}
