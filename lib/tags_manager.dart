import 'package:flutter/material.dart';
import 'package:notes_app_v0/repo.dart';

class TagsManager extends StatefulWidget {
  final Repo repo;
  final NoteData noteData;

  const TagsManager({super.key, required this.repo, required this.noteData});

  @override
  _TagsManagerState createState() => _TagsManagerState();
}

class _TagState {
  String tag;
  bool selected;

  _TagState(this.tag, this.selected);
}

class _TagsManagerState extends State<TagsManager> {
  List<_TagState> tags = [];

  late TextEditingController _newTagController;

  @override
  void initState() {
    super.initState();

    _newTagController = TextEditingController();

    tags = widget.repo.tags.values.map((tag) => _TagState(tag, false)).toList();
    for (final tag in widget.noteData.tags) {
      tags.firstWhere((element) => element.tag == tag).selected = true;
    }
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _assignTag(String tag) {
    // emit the event
    widget.repo.processEvent(
      TagAssigned(widget.noteData.id, tag),
      DateTime.now(),
    );

    // local state mutation
    if (!tags.any((element) => element.tag == tag)) {
      setState(() {
        // add and sort
        tags.add(_TagState(tag, true));
        tags.sort((a, b) => a.tag.compareTo(b.tag));
      });
    } else {
      setState(() {
        tags.firstWhere((element) => element.tag == tag).selected = true;
      });
    }
  }

  void _unassignTag(String tag) {
    // emit the event
    widget.repo.processEvent(
      TagUnassigned(widget.noteData.id, tag),
      DateTime.now(),
    );

    // local state mutation
    setState(() {
      tags.firstWhere((element) => element.tag == tag).selected = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _newTagController,
            decoration: InputDecoration(labelText: 'Add a new tag'),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                _assignTag(value);

                _newTagController.text = '';
                FocusScope.of(context).unfocus();
              }
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: tags.length,
            itemBuilder: (context, index) {
              return CheckboxListTile(
                title: Text(tags[index].tag),
                value: tags[index].selected,
                onChanged: (newValue) {
                  if (newValue != null && newValue) {
                    _assignTag(tags[index].tag);
                  } else {
                    _unassignTag(tags[index].tag);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
