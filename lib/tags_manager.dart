import 'package:flutter/material.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';
import 'package:notes_app_v0/controller_provider.dart';

class TagsManager extends StatefulWidget {
  final NoteData noteData;

  const TagsManager({super.key, required this.noteData});

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
  }

  // this is confusing, but it does work...
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repo = ControllerProvider.of(context).repo;

    tags = repo.tags.values.map((tag) => _TagState(tag, false)).toList();
    for (final tag in widget.noteData.tags) {
      tags.firstWhere((element) => element.tag == tag).selected = true;
    }
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _assignTag(BuildContext context, String tag) async {
    final controller = ControllerProvider.of(context);

    await controller.localEventSubmit(TagAssigned(widget.noteData.id, tag));

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

  Future<void> _unassignTag(BuildContext context, String tag) async {
    final controller = ControllerProvider.of(context);

    await controller.localEventSubmit(TagUnassigned(widget.noteData.id, tag));

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
                _assignTag(context, value);

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
                    _assignTag(context, tags[index].tag);
                  } else {
                    _unassignTag(context, tags[index].tag);
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
