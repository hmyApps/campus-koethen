// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/todo_folder.dart';
import '../domain/todo_store.dart';
import 'todos_controller.dart';

/// What happens to a folder's tasks when the folder itself is deleted. Tasks
/// never disappear silently — one of these must be chosen explicitly.
enum TodoFolderDeleteAction {
  /// Move the folder's tasks back to the default "no folder" area.
  moveToUnfiled,

  /// Delete the folder's tasks along with the folder.
  deleteTasks,
}

/// Loads and mutates the local folder list. Deleting a non-empty folder also
/// updates the affected to-dos through [TodosController], so the two
/// collections never drift apart.
///
/// Mutations run one after another, each against the list the previous one
/// published; otherwise two overlapping whole-list writes computed from the
/// same snapshot would silently drop one of the changes (F-09).
class TodoFoldersController extends AsyncNotifier<List<TodoFolder>> {
  int _seq = 0;
  Future<void> _tail = Future<void>.value();

  TodoStore get _store => ref.read(todoStoreProvider);

  @override
  Future<List<TodoFolder>> build() => _store.readFolders();

  List<TodoFolder> get _current => state.value ?? const <TodoFolder>[];

  /// Every mutation writes the WHOLE folder list back, so it must start from
  /// the list actually stored. A read still in flight is awaited; a read that
  /// failed refuses the write with a typed failure instead of persisting a
  /// list that only contains this one change (F-03).
  Future<void> _ensureReadable() async {
    if (state.isLoading) {
      try {
        await future;
      } catch (_) {
        // Reported below from the settled state.
      }
    }
    if (!state.hasValue) {
      throw TodoStoreFailure(
        TodoStoreOperation.read,
        state.error ?? StateError('Folder list not loaded'),
      );
    }
  }

  /// Queues [mutation] behind every earlier one. A failure is reported to
  /// this caller and does not block the mutations queued after it.
  Future<void> _serialized(Future<void> Function() mutation) {
    final Future<void> result = _tail.then((_) async {
      await _ensureReadable();
      await mutation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _persist(List<TodoFolder> next) async {
    await _store.writeFolders(next);
    state = AsyncData<List<TodoFolder>>(next);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Creates a new folder. Blank/whitespace-only names are ignored.
  Future<void> create(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _serialized(() {
      final TodoFolder folder = TodoFolder(
        id: _newId(),
        name: trimmed,
        createdAt: DateTime.now(),
      );
      return _persist(<TodoFolder>[..._current, folder]);
    });
  }

  /// Renames the folder with [id]. Blank/whitespace-only names are ignored.
  Future<void> rename(String id, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _serialized(
      () => _persist(<TodoFolder>[
        for (final TodoFolder f in _current)
          if (f.id == id) f.copyWith(name: trimmed) else f,
      ]),
    );
  }

  /// Deletes the folder with [id]. [action] decides what happens to the
  /// to-dos that were in it.
  ///
  /// The folder is only removed once its tasks were actually moved or
  /// deleted. If the task list could not be read, nothing changes and a typed
  /// failure is thrown — otherwise those tasks would stay filed under a folder
  /// that no longer exists.
  Future<void> delete(String id, TodoFolderDeleteAction action) => _serialized(
    () async {
      final TodosController todos = ref.read(todosControllerProvider.notifier);
      final bool tasksHandled = switch (action) {
        TodoFolderDeleteAction.moveToUnfiled => await todos.clearFolder(id),
        TodoFolderDeleteAction.deleteTasks => await todos.removeByFolder(id),
      };
      if (!tasksHandled) {
        throw TodoStoreFailure(
          TodoStoreOperation.read,
          StateError('Task list not loaded'),
        );
      }
      await _persist(_current.where((TodoFolder f) => f.id != id).toList());
    },
  );
}

/// Riverpod 3 auto-retries erroring providers with a backoff timer; that timer
/// outlives widget tests. Disable it — a failed local read stays an error and
/// refuses every write until the reader retries.
final AsyncNotifierProvider<TodoFoldersController, List<TodoFolder>>
todoFoldersControllerProvider =
    AsyncNotifierProvider<TodoFoldersController, List<TodoFolder>>(
      TodoFoldersController.new,
      retry: (_, _) => null,
    );
