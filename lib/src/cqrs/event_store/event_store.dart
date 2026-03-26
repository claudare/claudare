import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';

abstract class EventStore implements EventStoreCommand, EventStoreProjection {}
