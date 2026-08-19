import 'package:flutter/widgets.dart';

import 'note_application.dart';

// [ControllerProvider] injects the main app controller into the widget tree
class NoteApplicationProvider extends InheritedWidget {
  final NoteApplication application;

  const NoteApplicationProvider({
    super.key,
    required super.child,
    required this.application,
  });

  static NoteApplication of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NoteApplicationProvider>()!
        .application;
  }

  // https://www.wafrat.com/dependency-injection-in-flutter/
  // why is this needed idk...
  static NoteApplicationProvider ofInitStateContext(BuildContext context) {
    return context
            .getElementForInheritedWidgetOfExactType<NoteApplicationProvider>()!
            .widget
        as NoteApplicationProvider;
  }

  @override
  bool updateShouldNotify(NoteApplicationProvider oldWidget) {
    return application != oldWidget.application;
  }
}
