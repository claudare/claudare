import 'package:cqrs/src/cqrs/event_store/event_store_administration.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';

abstract interface class EventStore
    implements
        EventStoreCommand,
        EventStoreProjection,
        EventStoreAdministration {}
