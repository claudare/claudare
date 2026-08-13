import 'package:cqrs/src/cqrs/exception/runtime_repo_exception.dart';

import 'runtime_repo.dart';

class SafeRuntimeRepo {
  final RuntimeRepo _repo;

  const SafeRuntimeRepo(this._repo);

  Future<void> initialize() async {
    try {
      await _repo.initialize();
    } on Exception catch (e) {
      throw RuntimeRepoException('Failed to initialize runtime repo', cause: e);
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<int> getRuntimeVersion(String runtimeName) async {
    try {
      final value = await _repo.getRuntimeVersion(runtimeName);
      if (value < 0) {
        // TODO: is error appropriate here?
        // Mabe this is an exception? Or just an assertion?
        throw StateError('Invalid runtime version: $value');
      }
      return value;
    } on Exception catch (e) {
      throw RuntimeRepoException('Failed to get runtime version', cause: e);
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> setRuntimeVersion(String runtimeName, int version) async {
    if (version < 0) {
      throw StateError('Invalid runtime version: $version');
    }

    try {
      return _repo.setRuntimeVersion(runtimeName, version);
    } on Exception catch (e) {
      throw RuntimeRepoException('Failed to set runtime version', cause: e);
    } catch (e, st) {
      Error.throwWithStackTrace(e, st);
    }
  }
}
