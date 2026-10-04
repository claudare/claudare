import 'package:flutter/widgets.dart';

import 'package:notes_app/notes_app.dart';

// [ControllerProvider] injects the main app controller into the widget tree
class NotesAppProvider extends InheritedWidget {
  final NotesApp application;

  const NotesAppProvider({
    super.key,
    required super.child,
    required this.application,
  });

  static NotesApp of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NotesAppProvider>()!
        .application;
  }

  @override
  bool updateShouldNotify(NotesAppProvider oldWidget) {
    return application != oldWidget.application;
  }
}
