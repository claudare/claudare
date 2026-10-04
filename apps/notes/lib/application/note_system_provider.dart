import 'package:flutter/widgets.dart';

import 'note_system.dart';

/// Gives screens access to the saved settings and stores in [NoteSystem].
class NoteSystemProvider extends InheritedWidget {
  final NoteSystem system;

  const NoteSystemProvider({
    super.key,
    required super.child,
    required this.system,
  });

  static NoteSystem of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteSystemProvider>()!.system;

  @override
  bool updateShouldNotify(NoteSystemProvider oldWidget) =>
      system != oldWidget.system;
}
