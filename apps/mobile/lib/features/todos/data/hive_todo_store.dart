// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../domain/todo.dart';
import '../domain/todo_folder.dart';
import '../domain/todo_store.dart';

/// [TodoStore] backed by a local `hive_ce` box.
///
/// The list is user-authored data, not a cache. Every task is stored under its
/// stable ID so changing one entry does not encode and replace the whole list.
/// The legacy `items` array is migrated once on first open.
class HiveTodoStore implements TodoStore {
  factory HiveTodoStore({
    Box<String>? box,
    Future<void> Function()? initializeHive,
    Future<Box<String>> Function(String name)? openBox,
  }) => HiveTodoStore._(
    box,
    initializeHive ?? (() => Hive.initFlutter()),
    openBox ?? ((String name) => Hive.openBox<String>(name)),
  );

  HiveTodoStore._(this._box, this._initializeHive, this._openBox);

  static const String boxName = 'campus_todos_v1';
  static const String _itemsKey = 'items';
  static const String _foldersKey = 'folders';
  static const String _schemaKey = '_schema';
  static const String _schemaVersion = '2';
  static const String _todoPrefix = 'todo.';

  Box<String>? _box;
  final Future<void> Function() _initializeHive;
  final Future<Box<String>> Function(String name) _openBox;
  Future<Box<String>>? _readyFuture;

  Future<Box<String>> _ready() async {
    final Future<Box<String>>? pending = _readyFuture;
    if (pending != null) return pending;
    final Future<Box<String>> created = _openAndMigrate();
    _readyFuture = created;
    try {
      return await created;
    } catch (_) {
      if (identical(_readyFuture, created)) _readyFuture = null;
      rethrow;
    }
  }

  Future<Box<String>> _openAndMigrate() async {
    final Box<String> box = await _open();
    await _migrate(box);
    return box;
  }

  Future<Box<String>> _open() async {
    if (_box != null && _box!.isOpen) return _box!;
    try {
      await _initializeHive();
      _box = await _openBox(boxName);
      return _box!;
    } catch (error) {
      throw TodoStoreFailure(TodoStoreOperation.open, error);
    }
  }

  Future<void> _migrate(Box<String> box) async {
    try {
      if (box.get(_schemaKey) == _schemaVersion) return;
      final String? legacy = box.get(_itemsKey);
      final List<Todo> todos = legacy == null
          ? const <Todo>[]
          : _decodeTodos(legacy);
      await box.putAll(<String, String>{
        for (final Todo todo in todos)
          _todoKey(todo.id): jsonEncode(todo.toJson()),
        _schemaKey: _schemaVersion,
      });
      // The marker and migrated entries are committed together. A legacy copy
      // left behind by a cleanup failure is harmless and never read again.
      try {
        await box.delete(_itemsKey);
      } catch (_) {}
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.migrate, error);
    }
  }

  @override
  Future<List<Todo>> readAll() async {
    try {
      final Box<String> box = await _ready();
      final List<Todo> todos = <Todo>[];
      for (final Object key in box.keys) {
        if (key is! String || !key.startsWith(_todoPrefix)) continue;
        final String? raw = box.get(key);
        if (raw == null) throw const FormatException('Missing task value');
        final Todo? todo = Todo.fromJson(jsonDecode(raw));
        if (todo == null) throw const FormatException('Invalid task value');
        todos.add(todo);
      }
      todos.sort(_compareTodos);
      return todos;
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.read, error);
    }
  }

  @override
  Future<void> writeAll(List<Todo> todos) async {
    try {
      final Box<String> box = await _ready();
      final Set<String> nextKeys = todos
          .map((Todo todo) => _todoKey(todo.id))
          .toSet();
      await box.putAll(<String, String>{
        for (final Todo todo in todos)
          _todoKey(todo.id): jsonEncode(todo.toJson()),
      });
      await box.deleteAll(<Object>[
        for (final Object key in box.keys)
          if (key is String &&
              key.startsWith(_todoPrefix) &&
              !nextKeys.contains(key))
            key,
      ]);
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.write, error);
    }
  }

  @override
  Future<void> upsertTodo(Todo todo) => upsertTodos(<Todo>[todo]);

  @override
  Future<void> upsertTodos(Iterable<Todo> todos) async {
    try {
      final Box<String> box = await _ready();
      await box.putAll(<String, String>{
        for (final Todo todo in todos)
          _todoKey(todo.id): jsonEncode(todo.toJson()),
      });
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.write, error);
    }
  }

  @override
  Future<void> deleteTodo(String id) => deleteTodos(<String>[id]);

  @override
  Future<void> deleteTodos(Iterable<String> ids) async {
    try {
      final Box<String> box = await _ready();
      await box.deleteAll(ids.map(_todoKey));
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.write, error);
    }
  }

  @override
  Future<List<TodoFolder>> readFolders() async {
    try {
      final Box<String> box = await _ready();
      final String? raw = box.get(_foldersKey);
      if (raw == null) return const <TodoFolder>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Invalid folder list');
      final List<TodoFolder> folders = <TodoFolder>[];
      for (final Object? value in decoded) {
        final TodoFolder? folder = TodoFolder.fromJson(value);
        if (folder == null) throw const FormatException('Invalid folder');
        folders.add(folder);
      }
      return folders;
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.read, error);
    }
  }

  @override
  Future<void> writeFolders(List<TodoFolder> folders) async {
    try {
      final Box<String> box = await _ready();
      await box.put(
        _foldersKey,
        jsonEncode(folders.map((TodoFolder f) => f.toJson()).toList()),
      );
    } catch (error) {
      if (error is TodoStoreFailure) rethrow;
      throw TodoStoreFailure(TodoStoreOperation.write, error);
    }
  }

  static String _todoKey(String id) => '$_todoPrefix$id';

  static List<Todo> _decodeTodos(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid task list');
    return <Todo>[
      for (final Object? value in decoded)
        Todo.fromJson(value) ?? (throw const FormatException('Invalid task')),
    ];
  }

  static int _compareTodos(Todo left, Todo right) {
    final int byCreation = left.createdAt.compareTo(right.createdAt);
    return byCreation != 0 ? byCreation : left.id.compareTo(right.id);
  }
}
