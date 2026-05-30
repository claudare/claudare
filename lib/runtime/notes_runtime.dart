import 'package:core/cqrs.dart';
import 'package:core/device_id.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:notes_app_v0/command/create_note.dart';
import 'package:notes_app_v0/command/restore_note.dart';
import 'package:notes_app_v0/command/trash_note.dart';
import 'package:notes_app_v0/command/update_note_content.dart';
import 'package:notes_app_v0/command/update_note_title.dart';
import 'package:notes_app_v0/projection/note/note_projection.dart';
import 'package:notes_app_v0/projection/note/note_projection_repo.dart';
import 'package:notes_app_v0/read_model/resolved_note/resolved_note_read_model.dart';

class NotesRuntime {
  static int runtimeVersion = 3;

  // the read model is exposed directly
  final ResolvedNoteReadModel resolvedNoteReadModel;
  final NoteProjectionRepo noteProjectionRepo;

  late final CqrsRuntime _cqrsRuntime;
  late final CqrsCommands commands;

  NotesRuntime({
    required CqrsRuntimeConfig cqrsConfig,
    required this.noteProjectionRepo,
    required this.resolvedNoteReadModel,
  }) {
    // where does the deviceId come from?
    // does it come during the init phase or fetched automatically inside the CqrsRuntime?

    final noteProjection = NoteProjection(noteProjectionRepo);

    _cqrsRuntime = CqrsRuntime(
      config: cqrsConfig,
      projectors: [noteProjection],
      thisDeviceId: DeviceId.unassigned(),
      runtimeName: 'notes',
      runtimeVersion: NotesRuntime.runtimeVersion,
    );

    commands = CqrsCommands(
      createNote: _cqrsRuntime.bindCommand(CreateNote(), [noteProjection]),
      deleteNote: _cqrsRuntime.bindCommand(TrashNote(), [noteProjection]),
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
    await _cqrsRuntime.initializeProjections();
  }

  Future<void> rerunProjections() async {
    await _cqrsRuntime.rerunProjections();
  }
}

class CqrsCommands {
  final BoundCommand<CreateNoteInput> createNote;
  final BoundCommand<TrashNoteInput> deleteNote;
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
