// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/features/todos/data/hive_todo_store.dart';
import 'package:campus_koethen/features/todos/domain/todo.dart';
import 'package:campus_koethen/features/todos/domain/todo_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory directory;
  late Box<String> box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('todo-store-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>('todos');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('migrates the legacy list once without losing a task', () async {
    final List<Todo> legacy = <Todo>[
      Todo(id: 'a', title: 'Erste', createdAt: DateTime.utc(2026, 1, 1)),
      Todo(id: 'b', title: 'Zweite', createdAt: DateTime.utc(2026, 1, 2)),
    ];
    await box.put(
      'items',
      jsonEncode(legacy.map((Todo todo) => todo.toJson()).toList()),
    );
    final HiveTodoStore store = HiveTodoStore(box: box);

    expect((await store.readAll()).map((Todo todo) => todo.id), <String>[
      'a',
      'b',
    ]);
    expect(box.get('items'), isNull);
    expect(
      box.keys.where((dynamic key) => '$key'.startsWith('todo.')),
      hasLength(2),
    );

    final HiveTodoStore reopened = HiveTodoStore(box: box);
    expect((await reopened.readAll()).map((Todo todo) => todo.id), <String>[
      'a',
      'b',
    ]);
  });

  test(
    'updating one task leaves the other ID entry byte-for-byte intact',
    () async {
      final HiveTodoStore store = HiveTodoStore(box: box);
      final Todo first = Todo(
        id: 'a',
        title: 'Erste',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final Todo second = Todo(
        id: 'b',
        title: 'Zweite',
        createdAt: DateTime.utc(2026, 1, 2),
      );
      await store.writeAll(<Todo>[first, second]);
      final String? untouched = box.get('todo.b');

      await store.upsertTodo(first.copyWith(done: true));

      expect(box.get('todo.b'), untouched);
      expect((await store.readAll()).first.done, isTrue);
    },
  );

  test(
    'a corrupt legacy value is a typed migration error, not an empty list',
    () async {
      await box.put('items', '{not-json');
      final HiveTodoStore store = HiveTodoStore(box: box);

      await expectLater(
        store.readAll(),
        throwsA(
          isA<TodoStoreFailure>().having(
            (TodoStoreFailure failure) => failure.operation,
            'operation',
            TodoStoreOperation.migrate,
          ),
        ),
      );
    },
  );
}
