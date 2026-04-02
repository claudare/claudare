import 'package:flutter/widgets.dart';
import 'package:notes_app_v0/application.dart';

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

  @override
  bool updateShouldNotify(ApplicationProvider oldWidget) {
    print(
      'should ControllerProvider notify? ${application != oldWidget.application}',
    );
    return application != oldWidget.application;
  }
}
