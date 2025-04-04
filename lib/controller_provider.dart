import 'package:flutter/widgets.dart';
import 'package:notes_app_v0/controller.dart';

// [ControllerProvider] injects the main app controller into the widget tree
class ControllerProvider extends InheritedWidget {
  final Controller controller;

  const ControllerProvider({
    super.key,
    required super.child,
    required this.controller,
  });

  static Controller of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ControllerProvider>()!
        .controller;
  }

  @override
  bool updateShouldNotify(ControllerProvider oldWidget) {
    print(
      'should ControllerProvider notify? ${controller != oldWidget.controller}',
    );
    return controller != oldWidget.controller;
  }
}
