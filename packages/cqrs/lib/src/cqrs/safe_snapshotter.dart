import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/snapshotter.dart';

/// Recovers from snapshot storage exceptions while preserving fatal errors.
class SafeSnapshotter<T> implements Snapshotter<T> {
  final Snapshotter<T> _underlying;
  final Logger _logger;

  const SafeSnapshotter(this._underlying, {required Logger logger})
    : _logger = logger;

  @override
  Future<Snapshot<T>?> load(int aggregateVersion) async {
    try {
      return await _underlying.load(aggregateVersion);
    } on Exception catch (error, stackTrace) {
      _logger.error('Failed to load aggregate snapshot', error, stackTrace);
      return null;
    }
  }

  @override
  Future<void> save(int aggregateVersion, Snapshot<T> snapshot) async {
    try {
      await _underlying.save(aggregateVersion, snapshot);
    } on Exception catch (error, stackTrace) {
      _logger.error('Failed to save aggregate snapshot', error, stackTrace);
    }
  }
}
