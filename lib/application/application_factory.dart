import 'application.dart';

abstract class ApplicationFactory {
  Application create(String supportDir);
}
