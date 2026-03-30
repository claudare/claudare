import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:core/src/device_id.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

const appId = "TODO";

final migrations =
    SqliteMigrations()..add(
      SqliteMigration(1, (db) async {
        await db.exec('''CREATE TABLE stream(
          stream_id STRING,
          version INTEGER,
          PRIMARY KEY (stream_id)
        );''');
        await db.exec(
          'CREATE INDEX idx_stream_version ON stream(stream_id, version);',
        );

        // schema is the following:
        // app_id for multi-app tenancy. Currently just set to "TODO"
        // (app_id, stream_id, stream_version) for local consistency checks
        // (app_id, device_id, causal_sequence) for sync, event dependency tracking
        // (app_id, device_id, device_sequence) for sync, events are downloaded sequentially
        // (local_sequence) for fully offline projection catchup and playback
        await db.exec('''CREATE TABLE event(
          stream_id,
          stream_version INTEGER,
          kind,
          detail,
          occured_at,
          device_id,
          device_sequence INTEGER,
          causal_sequence INTEGER,
          local_sequence INTEGER,
          PRIMARY KEY (local_sequence)
        );'''); // app_sequence!

        await db.exec(
          'CREATE INDEX idx_device_sequence ON event(device_id, device_sequence);',
        );
        await db.exec(
          'CREATE INDEX idx_causal_sequence ON event(device_id, causal_sequence);',
        );

        // clocks maintained by sqlite
        await db.exec('''
          CREATE VIEW next_device_sequence AS
          SELECT device_id, COALESCE(MAX(device_sequence), 0) + 1 AS next_seq
          FROM event
          GROUP BY device_id;
        ''');

        await db.exec('''
          CREATE VIEW next_causal_sequence AS
          SELECT device_id, COALESCE(MAX(causal_sequence), 0) + 1 AS next_seq
          FROM event
          GROUP BY device_id;
        ''');

        await db.exec('''
          CREATE VIEW next_local_sequence AS
          SELECT COALESCE(MAX(local_sequence), 0) + 1 AS next_seq
          FROM event;
        ''');
      }),
    );

class EventDb {
  final IsolateSqlite _db;

  const EventDb(this._db);

  Future<void> migrate() async {
    await migrations.migrate(_db);
  }

  Future<GetStreamEventsResult> getStreamEvents(
    String _,
    String streamId,
    int count,
    int versionCursor,
  ) async {
    // could transact here!
    final originatingStreamVersion = await _db.queryValue<int>(
      "SELECT version FROM stream WHERE stream_id = ?",
      [streamId],
    );

    if (originatingStreamVersion == null) {
      return GetStreamEventsResult(originatingStreamVersion: 0, events: []);
    }

    final eventsResult = await _db.query(
      "SELECT kind, detail, occured_at, device_id, causal_sequence, stream_version FROM event WHERE stream_id = ? AND stream_version > ? ORDER BY stream_version ASC LIMIT ?",
      [streamId, versionCursor, count],
    );

    final events = List<StoredEventCommandRead>.generate(eventsResult.length, (
      i,
    ) {
      final row = eventsResult[i];

      return StoredEventCommandRead(
        encodedEvent: EncodedEvent(
          kind: row[0] as String,
          detail: row[1] as String,
        ),
        occuredAt: DateTime.fromMillisecondsSinceEpoch(
          row[2] as int,
          isUtc: true,
        ),
        deviceId: DeviceId(row[3] as int),
        causalSequence: row[4] as int,
        streamVersion: row[5] as int,
      );
    });

    return GetStreamEventsResult(
      originatingStreamVersion: originatingStreamVersion,
      events: events,
    );
  }

  Future<GetStreamInfoResult?> getStreamInfo(String _, String streamId) async {
    final row = await _db.queryRow(
      "SELECT device_id, causal_sequence, stream_version FROM event WHERE stream_id = ? ORDER BY stream_version DESC LIMIT 1",
      [streamId],
    );

    if (row == null) {
      return null;
    }

    return GetStreamInfoResult(
      causalSequencePair: DeviceIdSequencePair(
        DeviceId(row[0] as int),
        row[1] as int,
      ),
      originatingStreamVersion: row[2] as int,
    );
  }

  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    // TODO: save command + the vector...

    if (appends.localLocks.isEmpty || appends.events.isEmpty) {
      return SaveChangesResult(orders: []);
    }

    if (appends.localLocks.length == 1) {
      return await singleAppendEvents(command, appends);
    }

    throw UnimplementedError("Multi appends not supported yet");
  }

  Future<SaveChangesResult> singleAppendEvents(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    assert(appends.localLocks.length == 1);
    assert(appends.events.isNotEmpty);

    final deviceId = command.deviceId;
    final streamId = appends.localLocks.single.streamId;
    final originatingStreamVersion =
        appends.localLocks.single.originatingStreamVersion;

    return await _db.transaction((tx) {
      var streamVersion = 0;

      final streamVersionInDb = tx.queryValue<int>(
        "SELECT version FROM stream WHERE stream_id = ? LIMIT 1",

        [streamId],
      );

      if (streamVersionInDb == null) {
        tx.exec("INSERT INTO stream (stream_id, version) VALUES (?, 0)", [
          streamId,
        ]);
      } else {
        streamVersion = streamVersionInDb;
      }

      if (originatingStreamVersion != streamVersion) {
        throw ConcurrencyProblem();
      }

      final result = SaveChangesResult(orders: []);

      for (final event in appends.events) {
        // separate insertions for now to get it working
        final localSequence = tx.queryValue<int>(
          """INSERT INTO event (
            stream_id,
            stream_version,
            kind,
            detail,
            occured_at,
            device_id,
            device_sequence,
            causal_sequence,
            local_sequence
          ) VALUES (
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            COALESCE((SELECT next_seq FROM next_device_sequence WHERE device_id = ?), 1),
            COALESCE((SELECT next_seq FROM next_causal_sequence WHERE device_id = ?), 1),
            (SELECT next_seq FROM next_local_sequence)
          ) RETURNING local_sequence; """,
          [
            streamId,
            streamVersion + 1,
            event.encodedEvent.kind,
            event.encodedEvent.detail,
            event.occuredAt.millisecondsSinceEpoch,
            deviceId.value,
            deviceId.value,
            deviceId.value,
          ],
        );
        streamVersion++;

        if (localSequence == null) {
          throw StateError('localSequence is null');
        }

        result.orders.add(StreamAppendOrder(localSequence: localSequence));
      }

      tx.exec("UPDATE stream SET version = ? WHERE stream_id = ?", [
        streamVersion,
        streamId,
      ]);

      return result;
    });
  }

  Future<GetGlobalEventsResult> getGlobalEvents(
    String applicationId,
    int sequenceNumber,
    PatternFilter patternFilter,
    int count,
  ) async {
    final filterSql = patternToSQL(patternFilter);
    final values = await _db.query(
      """SELECT
        stream_id,
        kind,
        detail,
        local_sequence
      FROM event
      WHERE
        $filterSql AND
        local_sequence > ?
      ORDER BY local_sequence ASC
      LIMIT ?;""",
      [sequenceNumber, count],
    );

    return GetGlobalEventsResult(
      events: List<StoredEventProjectionRead>.generate(values.length, (i) {
        final row = values[i];
        return StoredEventProjectionRead(
          streamId: row[0] as String,
          encodedEvent: EncodedEvent(
            kind: row[1] as String,
            detail: row[2] as String,
          ),
          occuredAt: DateTime.fromMillisecondsSinceEpoch(
            row[3] as int,
            isUtc: true,
          ),
          localSequence: row[4] as int,
        );
      }),
      sequenceNumberCursor: values.isNotEmpty ? values.last[4] as int : null,
    );
  }
}

String patternToSQL(PatternFilter filter) {
  switch (filter.type) {
    case PatternFilterType.any:
      return '1 = 1';
    case PatternFilterType.exact:
      final value = filter.pattern;
      return 'stream_id = $value';
    case PatternFilterType.startsWith:
      final prefix = filter.pattern;
      return 'stream_id LIKE $prefix%';
  }
}
