import 'package:notes_app_v0/repo.dart';

/// [Services] is a singleton class that provides access to all global app services.
/// initialized in the main function, loading can be mocked in the tests?
/// I dont like singleton pattern, but I think its the best way to manage the
/// global dependencies
/// https://pub.dev/packages/get_it could be used for easier testing?
class Services {
  final Repo repo;

  static final Services _singleton = Services._privateConstructor(Repo.empty());
  factory Services() => _singleton;

  Services._privateConstructor(this.repo);
}
