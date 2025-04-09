import 'dart:async';

// TODO: would be nice to see connecting state too
enum SyncState { synced, uploading, downloading, disconnected }

class SyncStateManager {
  bool _isUploading = false;
  bool _isDownloading = false;
  bool _isConnected = false;

  final _statusController = StreamController<SyncState>.broadcast();

  SyncStateManager() {
    _emitStatus();
  }

  void dispose() {
    _statusController.close();
  }

  Stream<SyncState> get statusStream => _statusController.stream;

  bool get isUploading => _isUploading;
  bool get isDownloading => _isDownloading;

  SyncState get status {
    if (!_isConnected) return SyncState.disconnected;
    if (_isUploading) return SyncState.uploading;
    if (_isDownloading) return SyncState.downloading;
    return SyncState.synced;
  }

  void setConnected(bool state) {
    if (_isConnected == state) {
      throw StateError('Connection state is already $state');
    }
    _isConnected = state;
    _emitStatus();
  }

  void setUpload(bool state) {
    if (_isUploading == state) {
      throw StateError('Upload state is already $state');
    }
    _isUploading = state;
    _emitStatus();
  }

  void setDownload(bool state) {
    if (_isDownloading == state) {
      throw StateError('Download state is already $state');
    }
    _isDownloading = state;
    _emitStatus();
  }

  void _emitStatus() {
    _statusController.add(status);
  }
}
