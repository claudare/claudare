import 'package:flutter/material.dart';

class TagWidget extends StatelessWidget {
  final String tagName;
  final Function(String) onRemove;

  const TagWidget({super.key, required this.tagName, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(tagName),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      deleteIcon: Icon(Icons.close),
      onDeleted: () => onRemove(tagName),
      padding: EdgeInsets.all(4.0),
    );
  }
}
