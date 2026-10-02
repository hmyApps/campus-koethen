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
class TodoFoldersController extends AsyncNotifier<List<TodoFolder>> {
  int _seq = 0;

  TodoStore get _store => ref.read(todoStoreProvider);

  @override
  Future<List<TodoFolder>> build() => _store.readFolders();

  List<TodoFolder> get _current => state.value ?? const <TodoFolder>[];

  Future<void> _persist(List<TodoFolder> next) async {
    await _store.writeFolders(next);
    state = AsyncData<List<TodoFolder>>(next);
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Creates a new folder. Blank/whitespace-only names are ignored.
  Future<void> create(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final TodoFolder folder = TodoFolder(
      id: _newId(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    await _persist(<TodoFolder>[..._current, folder]);
  }

  /// Renames the folder with [id]. Blank/whitespace-only names are ignored.
  Future<void> rename(String id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _persist(<TodoFolder>[
      for (final TodoFolder f in _current)
        if (f.id == id) f.copyWith(name: trimmed) else f,
    ]);
  }

  /// Deletes the folder with [id]. [action] decides what happens to the
  /// to-dos that were in it.
  Future<void> delete(String id, TodoFolderDeleteAction action) async {
    switch (action) {
      case TodoFolderDeleteAction.moveToUnfiled:
        await ref.read(todosControllerProvider.notifier).clearFolder(id);
      case TodoFolderDeleteAction.deleteTasks:
        await ref.read(todosControllerProvider.notifier).removeByFolder(id);
    }
    await _persist(_current.where((TodoFolder f) => f.id != id).toList());
  }
}

/// Riverpod 3 auto-retries erroring providers with a backoff timer; that timer
/// outlives widget tests. Disable it — a failed local read just yields empty.
final AsyncNotifierProvider<TodoFoldersController, List<TodoFolder>>
todoFoldersControllerProvider =
    AsyncNotifierProvider<TodoFoldersController, List<TodoFolder>>(
      TodoFoldersController.new,
      retry: (_, _) => null,
    );
