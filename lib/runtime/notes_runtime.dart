import 'package:core/cqrs.dart';
import 'package:core/device_id.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:notes_app_v0/command/create_note.dart';
import 'package:notes_app_v0/command/delete_note.dart';
import 'package:notes_app_v0/command/restore_note.dart';
import 'package:notes_app_v0/command/update_note_content.dart';
import 'package:notes_app_v0/command/update_note_title.dart';
import 'package:notes_app_v0/projection/note/note_projection.dart';
import 'package:notes_app_v0/read_model/internal_note/internal_note_read_model.dart';
import 'package:notes_app_v0/read_model/resolved_note/resolved_note_read_model.dart';
import 'package:notes_app_v0/repo/note/note_internal_repo.dart';

class NotesRuntime {
  final EventStore eventStore;

  // the read model is exposed directly
  final ResolvedNoteReadModel resolvedNoteReadModel;
  final InternalNoteReadModel internalNoteReadModel;

  late final CqrsRuntime _cqrsRuntime;
  late final CqrsCommands commands;

  NotesRuntime({
    required this.eventStore,
    required CqrsRuntimeConfig cqrsConfig,
    required NoteInternalRepo noteInternalRepo,
    required this.resolvedNoteReadModel,
    required this.internalNoteReadModel,
  }) {
    // where does the deviceId come from?
    // does it come during the init phase or fetched automatically inside the CqrsRuntime?

    final noteProjection = NoteProjection(noteInternalRepo);

    _cqrsRuntime = CqrsRuntime(
      eventStore: eventStore,
      config: cqrsConfig,
      projectors: [noteProjection],
      thisDeviceId: DeviceId.unassigned(),
    );

    commands = CqrsCommands(
      createNote: _cqrsRuntime.bindCommand(CreateNote(), [noteProjection]),
      deleteNote: _cqrsRuntime.bindCommand(DeleteNote(), [noteProjection]),
      restoreNote: _cqrsRuntime.bindCommand(RestoreNote(), [noteProjection]),
      updateNoteContent: _cqrsRuntime.bindCommand(UpdateNoteContent(), [
        noteProjection,
      ]),
      updateNoteTitle: _cqrsRuntime.bindCommand(UpdateNoteTitle(), [
        noteProjection,
      ]),
    );
  }

  TimeProvider get timeProvider => _cqrsRuntime.timeProvider;
  IdGenerator get idGenerator => _cqrsRuntime.idGenerator;

  Future<void> initialize() async {
    await _cqrsRuntime.catchupAllProjections();
  }
}

class CqrsCommands {
  final BoundCommand<CreateNoteInput> createNote;
  final BoundCommand<DeleteNoteInput> deleteNote;
  final BoundCommand<RestoreNoteInput> restoreNote;
  final BoundCommand<UpdateNoteContentInput> updateNoteContent;
  final BoundCommand<UpdateNoteTitleInput> updateNoteTitle;

  const CqrsCommands({
    required this.createNote,
    required this.deleteNote,
    required this.restoreNote,
    required this.updateNoteContent,
    required this.updateNoteTitle,
  });
}
