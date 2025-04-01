import 'package:flutter/widgets.dart';
import 'package:notes_app_v0/repo.dart';

// [ServiceProvider] injects repo and other services into the widget tree
class ServiceProvider extends InheritedWidget {
  final Repo repo;

  const ServiceProvider({super.key, required super.child, required this.repo});

  static ServiceProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ServiceProvider>()!;
  }

  @override
  bool updateShouldNotify(ServiceProvider oldWidget) {
    return false;
  }
}
