library;

// cqrs runtime stuff
export 'src/cqrs/cqrs_runtime/cqrs_runtime.dart';

// event store
export 'src/cqrs/event_store/event_store.dart';
export 'src/cqrs/command/command_id.dart';
export 'src/cqrs/event/event_id.dart';
export 'src/cqrs/event_store/memory_event_store.dart';
export 'src/cqrs/event_store/sqlite_event_store.dart';

// event
export 'src/cqrs/event/event_codec.dart';
export 'src/cqrs/event/encoded_event.dart';
export 'src/cqrs/event/event_registry.dart';
export 'src/cqrs/event/event_envelope.dart';
export 'src/cqrs/event/stored_event.dart';

// command
export 'src/cqrs/command/command.dart';
export 'src/cqrs/command/stored_command.dart';
export 'src/cqrs/command/command_dependency.dart';
export 'src/cqrs/command/command_dependency_builder.dart';
export 'src/cqrs/command/command_context_api.dart';
export 'src/cqrs/command/command_context.dart' show CommandStream;

// aggregate
export 'src/cqrs/aggregate.dart';
export 'src/cqrs/snapshotter.dart';
export 'src/cqrs/memory_snapshotter.dart';

// stream route
export 'src/cqrs/stream_route/stream_route.dart';
export 'src/cqrs/stream_route/stream_route_all.dart';
export 'src/cqrs/stream_route/stream_route_wildcard.dart';

// exception
export 'src/cqrs/exception/command_exception.dart';
export 'src/cqrs/exception/concurrency_problem.dart';
export 'src/cqrs/exception/event_codec_exception.dart';
export 'src/cqrs/exception/event_store_exception.dart';
export 'src/cqrs/exception/runtime_database_exception.dart';
export 'src/cqrs/exception/runtime_store_exception.dart';
export 'src/cqrs/exception/stream_not_found_exception.dart';
export 'src/cqrs/exception/stream_already_exists_exception.dart';
