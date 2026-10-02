// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hive_todo_store.dart';
import '../domain/todo.dart';
import '../domain/todo_store.dart';

final Provider<TodoStore> todoStoreProvider = Provider<TodoStore>(
  (Ref ref) => HiveTodoStore(),
);

/// Loads and mutates the local to-do list. A mutation is published only after
/// its targeted store commit succeeds.
class TodosController extends AsyncNotifier<List<Todo>> {
  int _seq = 0;

  TodoStore get _store => ref.read(todoStoreProvider);

  @override
  Future<List<Todo>> build() => _store.readAll();

  List<Todo> get _current => state.value ?? const <Todo>[];
  bool get _readFailed => state.hasError && !state.hasValue;
  bool get acceptsWrites => !_readFailed;

  Future<bool> _commit(List<Todo> next, Future<void> Function() persist) async {
    if (_readFailed) return false;
    await persist();
    state = AsyncData<List<Todo>>(List<Todo>.unmodifiable(next));
    return true;
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  Future<bool> add(String title) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    final Todo todo = Todo(
      id: _newId(),
      title: trimmed,
      createdAt: DateTime.now(),
    );
    return _commit(<Todo>[..._current, todo], () => _store.upsertTodo(todo));
  }

  Future<void> toggle(String id) async {
    final Todo? original = _find(id);
    if (original == null) return;
    final Todo changed = original.copyWith(done: !original.done);
    await _commit(_replace(changed), () => _store.upsertTodo(changed));
  }

  Future<void> rename(String id, String title) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final Todo? original = _find(id);
    if (original == null) return;
    final Todo changed = original.copyWith(title: trimmed);
    await _commit(_replace(changed), () => _store.upsertTodo(changed));
  }

  Future<void> remove(String id) async {
    final List<Todo> next = _current.where((Todo t) => t.id != id).toList();
    if (next.length == _current.length) return;
    await _commit(next, () => _store.deleteTodo(id));
  }

  Future<void> clearCompleted() async {
    final List<Todo> removed = _current
        .where((Todo todo) => todo.done)
        .toList();
    if (removed.isEmpty) return;
    await _commit(
      _current.where((Todo todo) => !todo.done).toList(),
      () => _store.deleteTodos(removed.map((Todo todo) => todo.id)),
    );
  }

  Future<void> restore(Todo todo, {required int index}) async {
    if (_current.any((Todo t) => t.id == todo.id)) return;
    final List<Todo> next = List<Todo>.of(_current);
    next.insert(index.clamp(0, next.length), todo);
    await _commit(next, () => _store.upsertTodo(todo));
  }

  Future<void> restoreAll(List<({Todo todo, int index})> removed) async {
    if (removed.isEmpty) return;
    final List<Todo> next = List<Todo>.of(_current);
    final List<({Todo todo, int index})> ordered =
        List<({Todo todo, int index})>.of(removed)
          ..sort((a, b) => a.index.compareTo(b.index));
    final List<Todo> restored = <Todo>[];
    for (final ({Todo todo, int index}) item in ordered) {
      if (next.any((Todo t) => t.id == item.todo.id)) continue;
      next.insert(item.index.clamp(0, next.length), item.todo);
      restored.add(item.todo);
    }
    if (restored.isEmpty) return;
    await _commit(next, () => _store.upsertTodos(restored));
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    final Todo? original = _find(id);
    if (original == null) return;
    final Todo changed = original.copyWith(folderId: folderId);
    await _commit(_replace(changed), () => _store.upsertTodo(changed));
  }

  Future<void> clearFolder(String folderId) async {
    final List<Todo> changed = _current
        .where((Todo todo) => todo.folderId == folderId)
        .map((Todo todo) => todo.copyWith(folderId: null))
        .toList();
    if (changed.isEmpty) return;
    final Map<String, Todo> byId = <String, Todo>{
      for (final Todo todo in changed) todo.id: todo,
    };
    await _commit(<Todo>[
      for (final Todo todo in _current) byId[todo.id] ?? todo,
    ], () => _store.upsertTodos(changed));
  }

  Future<void> removeByFolder(String folderId) async {
    final List<Todo> removed = _current
        .where((Todo todo) => todo.folderId == folderId)
        .toList();
    if (removed.isEmpty) return;
    await _commit(
      _current.where((Todo todo) => todo.folderId != folderId).toList(),
      () => _store.deleteTodos(removed.map((Todo todo) => todo.id)),
    );
  }

  Todo? _find(String id) {
    for (final Todo todo in _current) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  List<Todo> _replace(Todo changed) => <Todo>[
    for (final Todo todo in _current)
      if (todo.id == changed.id) changed else todo,
  ];
}

final AsyncNotifierProvider<TodosController, List<Todo>>
todosControllerProvider = AsyncNotifierProvider<TodosController, List<Todo>>(
  TodosController.new,
  retry: (_, _) => null,
);
