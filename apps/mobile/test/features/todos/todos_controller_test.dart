// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

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

  Future<List<Todo>> build() => container.read(todosControllerProvider.future);
  List<Todo> current() => container.read(todosControllerProvider).requireValue;
  TodosController controller() =>
      container.read(todosControllerProvider.notifier);

  test('starts from an empty store', () async {
    expect(await build(), isEmpty);
  });

  test('reads items already persisted in the store', () async {
    await store.writeAll(<Todo>[
      Todo(id: '1', title: 'Persisted', createdAt: DateTime(2026)),
    ]);
    final List<Todo> loaded = await build();
    expect(loaded, hasLength(1));
    expect(loaded.single.title, 'Persisted');
  });

  test('add appends a trimmed, open item and persists it', () async {
    await build();
    await controller().add('  Milch kaufen  ');

    expect(current(), hasLength(1));
    expect(current().single.title, 'Milch kaufen');
    expect(current().single.done, isFalse);
    expect(await store.readAll(), hasLength(1));
  });

  test('add ignores blank or whitespace-only titles', () async {
    await build();
    await controller().add('   ');
    await controller().add('');

    expect(current(), isEmpty);
    expect(await store.readAll(), isEmpty);
  });

  test('toggle flips the done flag and persists', () async {
    await build();
    await controller().add('Aufgabe');
    final String id = current().single.id;

    await controller().toggle(id);
    expect(current().single.done, isTrue);
    expect((await store.readAll()).single.done, isTrue);

    await controller().toggle(id);
    expect(current().single.done, isFalse);
  });

  test('rename replaces the title but ignores blank input', () async {
    await build();
    await controller().add('Alt');
    final String id = current().single.id;

    await controller().rename(id, '  Neu  ');
    expect(current().single.title, 'Neu');

    await controller().rename(id, '   ');
    expect(current().single.title, 'Neu');
  });

  test('remove deletes only the matching item', () async {
    await build();
    await controller().add('A');
    await controller().add('B');
    final String firstId = current().first.id;

    await controller().remove(firstId);

    expect(current(), hasLength(1));
    expect(current().single.title, 'B');
    expect(await store.readAll(), hasLength(1));
  });

  test('clearCompleted removes done items and keeps open ones', () async {
    await build();
    await controller().add('Behalten');
    await controller().add('Erledigt');
    final String doneId = current().last.id;
    await controller().toggle(doneId);

    await controller().clearCompleted();

    expect(current(), hasLength(1));
    expect(current().single.title, 'Behalten');
    expect(await store.readAll(), hasLength(1));
  });

  test('assigns distinct ids to items added in quick succession', () async {
    await build();
    await controller().add('one');
    await controller().add('two');
    await controller().add('three');

    final Set<String> ids = current().map((Todo t) => t.id).toSet();
    expect(ids, hasLength(3));
  });

  test(
    'moveToFolder assigns the item to the given folder and persists',
    () async {
      await build();
      await controller().add('Aufgabe');
      final String id = current().single.id;

      await controller().moveToFolder(id, 'folder-1');

      expect(current().single.folderId, 'folder-1');
      expect((await store.readAll()).single.folderId, 'folder-1');
    },
  );

  test('moveToFolder(id, null) clears the folder', () async {
    await build();
    await controller().add('Aufgabe');
    final String id = current().single.id;
    await controller().moveToFolder(id, 'folder-1');

    await controller().moveToFolder(id, null);

    expect(current().single.folderId, isNull);
  });

  test(
    'clearFolder detaches every item in that folder, leaves others alone',
    () async {
      await build();
      await controller().add('A');
      await controller().add('B');
      final String idA = current()[0].id;
      final String idB = current()[1].id;
      await controller().moveToFolder(idA, 'folder-1');
      await controller().moveToFolder(idB, 'folder-2');

      await controller().clearFolder('folder-1');

      expect(current().firstWhere((Todo t) => t.id == idA).folderId, isNull);
      expect(
        current().firstWhere((Todo t) => t.id == idB).folderId,
        'folder-2',
      );
    },
  );

  test('removeByFolder deletes only items in that folder', () async {
    await build();
    await controller().add('A');
    await controller().add('B');
    final String idA = current()[0].id;
    final String idB = current()[1].id;
    await controller().moveToFolder(idA, 'folder-1');
    await controller().moveToFolder(idB, 'folder-2');

    await controller().removeByFolder('folder-1');

    expect(current(), hasLength(1));
    expect(current().single.id, idB);
    expect(await store.readAll(), hasLength(1));
  });

  group('a failed read never destroys the stored list', () {
    test('add is refused while the store could not be read', () async {
      // TODO-1. Every mutation writes the WHOLE list back, and with a failed
      // read the controller's view of it is empty — so adding one task
      // persisted a list of exactly that task, wiping everything that was
      // actually on the device.
      final _UnreadableTodoStore broken = _UnreadableTodoStore(<Todo>[
        Todo(id: '1', title: 'Wichtig', createdAt: DateTime(2026)),
        Todo(id: '2', title: 'Auch wichtig', createdAt: DateTime(2026)),
      ]);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(broken)],
      );
      addTearDown(c.dispose);

      await expectLater(
        c.read(todosControllerProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(c.read(todosControllerProvider).hasError, isTrue);

      await c.read(todosControllerProvider.notifier).add('Neue Aufgabe');

      // The two stored tasks are untouched, and nothing was written over them.
      expect(broken.stored, hasLength(2));
      expect(broken.writes, 0);
    });

    test('clearCompleted and remove are refused too', () async {
      final _UnreadableTodoStore broken = _UnreadableTodoStore(<Todo>[
        Todo(id: '1', title: 'Wichtig', createdAt: DateTime(2026), done: true),
      ]);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(broken)],
      );
      addTearDown(c.dispose);
      await expectLater(
        c.read(todosControllerProvider.future),
        throwsA(isA<StateError>()),
      );

      await c.read(todosControllerProvider.notifier).clearCompleted();
      await c.read(todosControllerProvider.notifier).remove('1');

      expect(broken.stored, hasLength(1));
      expect(broken.writes, 0);
    });
  });

  test(
    'a failed commit leaves the published and stored task unchanged',
    () async {
      final Todo original = Todo(
        id: '1',
        title: 'Wichtig',
        createdAt: DateTime(2026),
      );
      final _FailingWriteTodoStore broken = _FailingWriteTodoStore(original);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(broken)],
      );
      addTearDown(c.dispose);
      await c.read(todosControllerProvider.future);

      await expectLater(
        c.read(todosControllerProvider.notifier).toggle(original.id),
        throwsA(
          isA<TodoStoreFailure>().having(
            (TodoStoreFailure failure) => failure.operation,
            'operation',
            TodoStoreOperation.write,
          ),
        ),
      );

      expect(c.read(todosControllerProvider).requireValue.single.done, isFalse);
      expect(broken.stored.single.done, isFalse);
    },
  );

  group('overlapping mutations never lose an update (F-09)', () {
    test(
      'a task deleted while another write is in flight stays deleted',
      () async {
        // `toggle(a)` computed its next list as [a', b] and then waited for the
        // store; `remove(b)` meanwhile published [a]. When the toggle's write
        // finished it published its stale [a', b] — b was back on screen
        // although the store no longer had it.
        final _GatedWriteTodoStore gated = _GatedWriteTodoStore();
        await gated.writeAll(<Todo>[
          Todo(id: 'a', title: 'Erste', createdAt: DateTime(2026)),
          Todo(id: 'b', title: 'Zweite', createdAt: DateTime(2026)),
        ]);
        final ProviderContainer c = ProviderContainer(
          overrides: <Override>[todoStoreProvider.overrideWithValue(gated)],
        );
        addTearDown(c.dispose);
        await c.read(todosControllerProvider.future);
        final TodosController todos = c.read(todosControllerProvider.notifier);

        gated.holdUpserts();
        final Future<void> toggling = todos.toggle('a');
        final Future<void> removing = todos.remove('b');
        await pumpEventQueue();
        gated.releaseUpserts();
        await Future.wait(<Future<void>>[toggling, removing]);

        final List<Todo> shown = c.read(todosControllerProvider).requireValue;
        expect(shown.map((Todo t) => t.id), <String>['a']);
        expect(shown.single.done, isTrue);
        expect((await gated.readAll()).map((Todo t) => t.id), <String>['a']);
      },
    );

    test('two quick adds both survive', () async {
      await build();
      final Future<bool> first = controller().add('Eins');
      final Future<bool> second = controller().add('Zwei');
      await Future.wait(<Future<bool>>[first, second]);

      expect(current().map((Todo t) => t.title), <String>['Eins', 'Zwei']);
      expect(await store.readAll(), hasLength(2));
    });

    test('a failed write does not block the next mutation', () async {
      final _GatedWriteTodoStore gated = _GatedWriteTodoStore();
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[todoStoreProvider.overrideWithValue(gated)],
      );
      addTearDown(c.dispose);
      await c.read(todosControllerProvider.future);
      final TodosController todos = c.read(todosControllerProvider.notifier);

      gated.failNextUpsert = true;
      await expectLater(todos.add('Kaputt'), throwsA(isA<TodoStoreFailure>()));
      expect(await todos.add('Heil'), isTrue);

      expect(
        c.read(todosControllerProvider).requireValue.map((Todo t) => t.title),
        <String>['Heil'],
      );
    });
  });

  group('undo puts a task back where it was', () {
    test('restore inserts at the original index', () async {
      await store.writeAll(<Todo>[
        Todo(id: 'a', title: 'Erste', createdAt: DateTime(2026)),
        Todo(id: 'b', title: 'Zweite', createdAt: DateTime(2026)),
        Todo(id: 'c', title: 'Dritte', createdAt: DateTime(2026)),
      ]);
      await build();

      final Todo middle = current()[1];
      await controller().remove(middle.id);
      expect(current().map((Todo t) => t.id), <String>['a', 'c']);

      await controller().restore(middle, index: 1);
      // Back in the middle, not appended — "undo" has to mean undo.
      expect(current().map((Todo t) => t.id), <String>['a', 'b', 'c']);
    });

    test('restoreAll puts every cleared task back in place', () async {
      await store.writeAll(<Todo>[
        Todo(id: 'a', title: 'Offen', createdAt: DateTime(2026)),
        Todo(id: 'b', title: 'Fertig', createdAt: DateTime(2026), done: true),
        Todo(id: 'c', title: 'Offen 2', createdAt: DateTime(2026)),
        Todo(id: 'd', title: 'Fertig 2', createdAt: DateTime(2026), done: true),
      ]);
      await build();

      final List<({Todo todo, int index})> removed = <({Todo todo, int index})>[
        (todo: current()[1], index: 1),
        (todo: current()[3], index: 3),
      ];
      await controller().clearCompleted();
      expect(current().map((Todo t) => t.id), <String>['a', 'c']);

      await controller().restoreAll(removed);
      expect(current().map((Todo t) => t.id), <String>['a', 'b', 'c', 'd']);
    });
  });
}

/// A store whose read always fails, keeping its contents intact.
class _UnreadableTodoStore implements TodoStore {
  _UnreadableTodoStore(this.stored);

  List<Todo> stored;
  List<TodoFolder> folders = const <TodoFolder>[];
  int writes = 0;

  @override
  Future<List<Todo>> readAll() async => throw StateError('box unavailable');

  @override
  Future<void> writeAll(List<Todo> todos) async {
    writes++;
    stored = List<Todo>.of(todos);
  }

  @override
  Future<void> upsertTodo(Todo todo) async {
    writes++;
  }

  @override
  Future<void> upsertTodos(Iterable<Todo> todos) async {
    writes++;
  }

  @override
  Future<void> deleteTodo(String id) async {
    writes++;
  }

  @override
  Future<void> deleteTodos(Iterable<String> ids) async {
    writes++;
  }

  @override
  Future<List<TodoFolder>> readFolders() async => folders;

  @override
  Future<void> writeFolders(List<TodoFolder> next) async => folders = next;
}

/// An in-memory store whose upserts can be held back, or fail once.
class _GatedWriteTodoStore extends InMemoryTodoStore {
  Completer<void>? _gate;
  bool failNextUpsert = false;

  void holdUpserts() => _gate = Completer<void>();

  void releaseUpserts() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> upsertTodos(Iterable<Todo> todos) async {
    final Completer<void>? gate = _gate;
    if (gate != null) await gate.future;
    if (failNextUpsert) {
      failNextUpsert = false;
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));
    }
    await super.upsertTodos(todos);
  }
}

class _FailingWriteTodoStore implements TodoStore {
  _FailingWriteTodoStore(Todo todo) : stored = <Todo>[todo];

  List<Todo> stored;

  @override
  Future<List<Todo>> readAll() async => List<Todo>.of(stored);

  @override
  Future<void> writeAll(List<Todo> todos) async =>
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));

  @override
  Future<void> upsertTodo(Todo todo) async =>
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));

  @override
  Future<void> upsertTodos(Iterable<Todo> todos) async =>
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));

  @override
  Future<void> deleteTodo(String id) async =>
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));

  @override
  Future<void> deleteTodos(Iterable<String> ids) async =>
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));

  @override
  Future<List<TodoFolder>> readFolders() async => const <TodoFolder>[];

  @override
  Future<void> writeFolders(List<TodoFolder> folders) async {}
}
