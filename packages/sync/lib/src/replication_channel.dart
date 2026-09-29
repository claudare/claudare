import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';

/// An ordered connection without transport duplicates in either direction.
///
/// Messages are delivered or the connection closes. Closure ends both
/// directions, with unacknowledged delivery unknown. Detection may be delayed.
/// A new connection requires a new [ReplicationChannel].
typedef ReplicationChannel = StreamChannel<ReplicationMessage>;
