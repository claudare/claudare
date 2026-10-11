import 'package:flutter/widgets.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:support_directory/support_directory.dart';

/// Gives screens access to Notes resources and local storage.
class NoteBootstrapProvider extends InheritedWidget {
  final NoteBootstrap bootstrap;
  final SupportDirectory supportDirectory;

  const NoteBootstrapProvider({
    super.key,
    required super.child,
    required this.bootstrap,
    required this.supportDirectory,
  });

  static NoteBootstrapProvider of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteBootstrapProvider>()!;

  @override
  bool updateShouldNotify(NoteBootstrapProvider oldWidget) =>
      bootstrap != oldWidget.bootstrap ||
      supportDirectory != oldWidget.supportDirectory;
}
