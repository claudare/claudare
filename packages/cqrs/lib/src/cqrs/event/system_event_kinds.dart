/// Framework-owned event kinds. Applications cannot register `$` kinds.
abstract final class SystemEventKinds {
  /// A permanent stream deletion marker with empty bytes.
  static const streamDeleted = r'$streamDeleted';

  /// An erased historical event retaining its identity and empty bytes.
  static const eventErased = r'$eventErased';
}
