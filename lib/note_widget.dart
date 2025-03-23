import 'package:flutter/material.dart';

import 'package:notes_app_v0/note_model.dart';

class NoteStatefulWidget extends StatefulWidget {
  final NoteModel note;

  const NoteStatefulWidget({super.key, required this.note});

  @override
  _NoteStatefulWidgetState createState() => _NoteStatefulWidgetState();
}

class _NoteStatefulWidgetState extends State<NoteStatefulWidget> {
  late TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController(text: widget.note.body);

    _bodyController.addListener(() {
      widget.note.updateBody(_bodyController.text);
    });
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        children: [
          Text(widget.note.title, style: TextStyle(fontSize: 18.0)),
          SizedBox(height: 4.0),
          TextField(
            controller: _bodyController,
            decoration: InputDecoration(
              labelText: 'Body',
              border: OutlineInputBorder(),
            ),
            maxLines: null, // Allows multi-line text input
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 16.0),
          ),
        ],
      ),
    );
  }
}
