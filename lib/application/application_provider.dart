import 'package:flutter/widgets.dart';

import 'application.dart';

// [ControllerProvider] injects the main app controller into the widget tree
class ApplicationProvider extends InheritedWidget {
  final Application application;

  const ApplicationProvider({
    super.key,
    required super.child,
    required this.application,
  });

  static Application of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ApplicationProvider>()!
        .application;
  }

  // https://www.wafrat.com/dependency-injection-in-flutter/
  static ApplicationProvider ofInitStateContext(BuildContext context) {
    return context
            .getElementForInheritedWidgetOfExactType<ApplicationProvider>()!
            .widget
        as ApplicationProvider;
  }

  @override
  bool updateShouldNotify(ApplicationProvider oldWidget) {
    return application != oldWidget.application;
  }
}
