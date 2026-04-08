import 'application.dart';

abstract class ApplicationFactory {
  Future<Application> create();
}
