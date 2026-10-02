// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'todo.dart';
import 'todo_folder.dart';

enum TodoStoreOperation { open, migrate, read, write }

/// A typed persistence failure for user-authored task data.
class TodoStoreFailure implements Exception {
  const TodoStoreFailure(this.operation, this.cause);

  final TodoStoreOperation operation;
  final Object cause;

  @override
  String toString() => 'TodoStoreFailure($operation, $cause)';
}

/// Port for local, on-device persistence of tasks and their folders.
///
/// Tasks have stable IDs and support entry-level mutations. [writeAll] exists
/// for imports and test setup; production mutations use the targeted methods.
/// Store failures are never converted to an empty list or a successful write.
abstract interface class TodoStore {
  Future<List<Todo>> readAll();
  Future<void> writeAll(List<Todo> todos);
  Future<void> upsertTodo(Todo todo);
  Future<void> upsertTodos(Iterable<Todo> todos);
  Future<void> deleteTodo(String id);
  Future<void> deleteTodos(Iterable<String> ids);

  Future<List<TodoFolder>> readFolders();
  Future<void> writeFolders(List<TodoFolder> folders);
}

/// A volatile in-memory store, used as a safe fallback and in tests.
class InMemoryTodoStore implements TodoStore {
  List<Todo> _items = const <Todo>[];
  List<TodoFolder> _folders = const <TodoFolder>[];

  @override
  Future<List<Todo>> readAll() async => List<Todo>.of(_items);

  @override
  Future<void> writeAll(List<Todo> todos) async =>
      _items = List<Todo>.of(todos);

  @override
  Future<void> upsertTodo(Todo todo) => upsertTodos(<Todo>[todo]);

  @override
  Future<void> upsertTodos(Iterable<Todo> todos) async {
    final List<Todo> next = List<Todo>.of(_items);
    for (final Todo todo in todos) {
      final int index = next.indexWhere((Todo item) => item.id == todo.id);
      if (index < 0) {
        next.add(todo);
      } else {
        next[index] = todo;
      }
    }
    _items = next;
  }

  @override
  Future<void> deleteTodo(String id) => deleteTodos(<String>[id]);

  @override
  Future<void> deleteTodos(Iterable<String> ids) async {
    final Set<String> removed = ids.toSet();
    _items = _items.where((Todo todo) => !removed.contains(todo.id)).toList();
  }

  @override
  Future<List<TodoFolder>> readFolders() async => List<TodoFolder>.of(_folders);

  @override
  Future<void> writeFolders(List<TodoFolder> folders) async =>
      _folders = List<TodoFolder>.of(folders);
}
