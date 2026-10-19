import 'package:stream_channel/stream_channel.dart';

import 'blob_replication_message.dart';

/// An ordered, bidirectional connection for one blob protocol session.
/// Closing the channel ends the session; its caller owns replacement.
typedef BlobReplicationChannel = StreamChannel<BlobReplicationMessage>;
