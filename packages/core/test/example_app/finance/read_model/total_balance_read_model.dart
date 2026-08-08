import 'package:core/cqrs.dart';

// just an example. storing a number basically.
class TotalBalanceReadModel {
  int _totalBalance = 0;
  int _lastLocalSequence = 0;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  TotalBalanceReadModel();

  // Future<void> init() async {
  //   _isInitialized = true;
  // }

  Future<void> reset() async {
    _isInitialized = true;
    _totalBalance = 0;
  }

  Future<ProjectionCheckpoint> checkpoint() async {
    if (!_isInitialized) {
      return ProjectionCheckpoint.notInitialized();
    }

    return ProjectionCheckpoint(_lastLocalSequence);
  }

  // mutations (can be moved out, easier to do with sql)
  Future<void> store(int value, int localSequence) async {
    // should check everywhere
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    await Future.delayed(Duration.zero);

    _totalBalance = value;
    _lastLocalSequence = localSequence;
  }

  // Read methods below

  Future<int> get() async {
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    await Future.delayed(Duration.zero);

    return _totalBalance;
  }
}
