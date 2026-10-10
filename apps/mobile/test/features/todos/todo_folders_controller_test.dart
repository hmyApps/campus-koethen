// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/todos/application/todo_folders_controller.dart';
import 'package:campus_koethen/features/todos/application/todos_controller.dart';
import 'package:campus_koethen/features/todos/domain/todo.dart';
import 'package:campus_koethen/features/todos/domain/todo_folder.dart';
import 'package:campus_koethen/features/todos/domain/todo_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTodoStore store;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryTodoStore();
    container = ProviderContainer(
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
  });

  Future<List<TodoFolder>> build() =>
      container.read(todoFoldersControllerProvider.future);
  List<TodoFolder> current() =>
      container.read(todoFoldersControllerProvider).requireValue;
  TodoFoldersController controller() =>
      container.read(todoFoldersControllerProvider.notifier);
  TodosController todos() => container.read(todosControllerProvider.notifier);

  test('starts from an empty store', () async {
    expect(await build(), isEmpty);
  });

  test('create appends a trimmed folder and persists it', () async {
    await build();
    await controller().create('  Uni  ');

    expect(current(), hasLength(1));
    expect(current().single.name, 'Uni');
    expect(await store.readFolders(), hasLength(1));
  });

  test('create ignores blank or whitespace-only names', () async {
    await build();
    await controller().create('   ');

    expect(current(), isEmpty);
    expect(await store.readFolders(), isEmpty);
  });

  test('rename replaces the name but ignores blank input', () async {
    await build();
    await controller().create('Alt');
    final String id = current().single.id;

    await controller().rename(id, '  Neu  ');
    expect(current().single.name, 'Neu');

    await controller().rename(id, '   ');
    expect(current().single.name, 'Neu');
  });

  test(
    'delete(moveToUnfiled) removes the folder and clears it from its tasks',
    () async {
      await build();
      await container.read(todosControllerProvider.future);
      await controller().create('Uni');
      final String folderId = current().single.id;
      await todos().add('Aufgabe');
      final String todoId = container
          .read(todosControllerProvider)
          .requireValue
          .single
          .id;
      await todos().moveToFolder(todoId, folderId);

      await controller().delete(folderId, TodoFolderDeleteAction.moveToUnfiled);

      expect(current(), isEmpty);
      final List<Todo> remaining = container
          .read(todosControllerProvider)
          .requireValue;
      expect(remaining, hasLength(1));
      expect(remaining.single.folderId, isNull);
    },
  );

  test(
    'delete(deleteTasks) removes the folder and its tasks, keeps others',
    () async {
      await build();
      await container.read(todosControllerProvider.future);
      await controller().create('Uni');
      final String folderId = current().single.id;
      await todos().add('Im Ordner');
      await todos().add('Woanders');
      final List<Todo> added = container
          .read(todosControllerProvider)
          .requireValue;
      await todos().moveToFolder(added[0].id, folderId);

      await controller().delete(folderId, TodoFolderDeleteAction.deleteTasks);

      expect(current(), isEmpty);
      final List<Todo> remaining = container
          .read(todosControllerProvider)
          .requireValue;
      expect(remaining, hasLength(1));
      expect(remaining.single.title, 'Woanders');
    },
  );

  group('a failed or unfinished read never destroys the stored folders', () {
    // F-03. Every folder mutation writes the WHOLE list back. With a failed
    // read the controller's view of it is empty, so creating one folder used
    // to persist a list of exactly that folder — every folder actually on the
    // device was gone.
    final List<TodoFolder> stored = <TodoFolder>[
      TodoFolder(id: 'f1', name: 'Uni', createdAt: DateTime(2026)),
      TodoFolder(id: 'f2', name: 'Privat', createdAt: DateTime(2026)),
    ];

    test('create is refused while the folders could not be read', () async {
      final _UnreadableFolderStore broken = _UnreadableFolderStore(stored);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(broken)],
      );
      addTearDown(c.dispose);
      await expectLater(
        c.read(todoFoldersControllerProvider.future),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        c.read(todoFoldersControllerProvider.notifier).create('Neu'),
        throwsA(isA<TodoStoreFailure>()),
      );

      expect(broken.folders, stored);
      expect(broken.folderWrites, 0);
    });

    test('rename and delete are refused too', () async {
      final _UnreadableFolderStore broken = _UnreadableFolderStore(stored);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(broken)],
      );
      addTearDown(c.dispose);
      await expectLater(
        c.read(todoFoldersControllerProvider.future),
        throwsA(isA<StateError>()),
      );
      final TodoFoldersController folders = c.read(
        todoFoldersControllerProvider.notifier,
      );

      await expectLater(
        folders.rename('f1', 'Neu'),
        throwsA(isA<TodoStoreFailure>()),
      );
      await expectLater(
        folders.delete('f1', TodoFolderDeleteAction.moveToUnfiled),
        throwsA(isA<TodoStoreFailure>()),
      );

      expect(broken.folders, stored);
      expect(broken.folderWrites, 0);
    });

    test('create waits for a read still in flight instead of writing over '
        'it', () async {
      final _SlowFolderStore slow = _SlowFolderStore(stored);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(slow)],
      );
      addTearDown(c.dispose);
      c.listen(todoFoldersControllerProvider, (_, _) {});
      expect(c.read(todoFoldersControllerProvider).isLoading, isTrue);

      final Future<void> creating = c
          .read(todoFoldersControllerProvider.notifier)
          .create('Neu');
      slow.releaseRead();
      await creating;

      expect((await slow.readFolders()).map((TodoFolder f) => f.name), <String>[
        'Uni',
        'Privat',
        'Neu',
      ]);
      expect(
        c
            .read(todoFoldersControllerProvider)
            .requireValue
            .map((TodoFolder f) => f.name),
        <String>['Uni', 'Privat', 'Neu'],
      );
    });

    test('delete keeps the folder when its tasks could not be detached', () async {
      // The to-do list failed to load, so `clearFolder` cannot touch the tasks
      // that still point at this folder. Removing the folder anyway would leave
      // them filed under a folder that no longer exists.
      final _UnreadableTodosStore broken = _UnreadableTodosStore(stored);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(broken)],
      );
      addTearDown(c.dispose);
      await c.read(todoFoldersControllerProvider.future);
      await expectLater(
        c.read(todosControllerProvider.future),
        throwsA(isA<StateError>()),
      );

      for (final TodoFolderDeleteAction action
          in TodoFolderDeleteAction.values) {
        await expectLater(
          c.read(todoFoldersControllerProvider.notifier).delete('f1', action),
          throwsA(isA<TodoStoreFailure>()),
          reason: '$action',
        );
      }

      expect(broken.folders, stored);
      expect(c.read(todoFoldersControllerProvider).requireValue, hasLength(2));
    });
  });

  test('overlapping folder mutations never lose an update (F-09)', () async {
    // Both creates used to compute "current + mine" from the same snapshot,
    // so the second whole-list write silently dropped the first folder.
    await build();
    final Future<void> first = controller().create('Uni');
    final Future<void> second = controller().create('Privat');
    await Future.wait(<Future<void>>[first, second]);

    expect(current().map((TodoFolder f) => f.name), <String>['Uni', 'Privat']);
    expect((await store.readFolders()).map((TodoFolder f) => f.name), <String>[
      'Uni',
      'Privat',
    ]);

    final String uniId = current().first.id;
    final Future<void> renaming = controller().rename(uniId, 'Studium');
    final Future<void> creating = controller().create('Sport');
    await Future.wait(<Future<void>>[renaming, creating]);

    expect((await store.readFolders()).map((TodoFolder f) => f.name), <String>[
      'Studium',
      'Privat',
      'Sport',
    ]);
  });
}

/// Folders cannot be read; tasks are an empty, healthy list.
class _UnreadableFolderStore extends InMemoryTodoStore {
  _UnreadableFolderStore(this.folders);

  List<TodoFolder> folders;
  int folderWrites = 0;

  @override
  Future<List<TodoFolder>> readFolders() async =>
      throw StateError('box unavailable');

  @override
  Future<void> writeFolders(List<TodoFolder> next) async {
    folderWrites++;
    folders = List<TodoFolder>.of(next);
  }
}

/// Folders are readable, but only once [releaseRead] is called.
class _SlowFolderStore extends InMemoryTodoStore {
  _SlowFolderStore(List<TodoFolder> folders) {
    _folders = List<TodoFolder>.of(folders);
  }

  late List<TodoFolder> _folders;
  final Completer<void> _gate = Completer<void>();

  void releaseRead() => _gate.complete();

  @override
  Future<List<TodoFolder>> readFolders() async {
    await _gate.future;
    return List<TodoFolder>.of(_folders);
  }

  @override
  Future<void> writeFolders(List<TodoFolder> next) async =>
      _folders = List<TodoFolder>.of(next);
}

/// Folders are readable; the task list is not.
class _UnreadableTodosStore extends InMemoryTodoStore {
  _UnreadableTodosStore(this.folders);

  List<TodoFolder> folders;

  @override
  Future<List<Todo>> readAll() async => throw StateError('box unavailable');

  @override
  Future<List<TodoFolder>> readFolders() async => List<TodoFolder>.of(folders);

  @override
  Future<void> writeFolders(List<TodoFolder> next) async =>
      folders = List<TodoFolder>.of(next);
}
