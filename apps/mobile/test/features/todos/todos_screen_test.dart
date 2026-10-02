// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/features/todos/application/todos_controller.dart';
import 'package:campus_koethen/features/todos/domain/todo.dart';
import 'package:campus_koethen/features/todos/domain/todo_folder.dart';
import 'package:campus_koethen/features/todos/domain/todo_store.dart';
import 'package:campus_koethen/features/todos/presentation/todos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/pump_app.dart';

void main() {
  testWidgets('shows the empty state when there are no tasks', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[
        todoStoreProvider.overrideWithValue(InMemoryTodoStore()),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Keine Aufgaben'), findsOneWidget);
  });

  testWidgets('adds a task via the input field', (WidgetTester tester) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Einkaufen');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Einkaufen'), findsOneWidget);
    expect(find.text('Keine Aufgaben'), findsNothing);
    expect(await store.readAll(), hasLength(1));
  });

  testWidgets('a failed add keeps the text and shows a storage error', (
    WidgetTester tester,
  ) async {
    final _WriteFailingTodoStore store = _WriteFailingTodoStore();
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hausarbeit abgeben');
    await tester.tap(find.byIcon(AppIcons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Hausarbeit abgeben'), findsOneWidget);
    expect(
      find.text(
        'Die Änderung konnte nicht auf diesem Gerät gespeichert werden. '
        'Versuche es erneut.',
      ),
      findsOneWidget,
    );
    expect(await store.readAll(), isEmpty);
  });

  testWidgets('renames a task without failing while the dialog closes', (
    WidgetTester tester,
  ) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await store.writeAll(<Todo>[
      Todo(id: '1', title: 'Alter Name', createdAt: DateTime(2026)),
    ]);
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aufgabe umbenennen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Neuer Name');
    await tester.tap(find.widgetWithText(FilledButton, 'Umbenennen'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Neuer Name'), findsOneWidget);
    expect((await store.readAll()).single.title, 'Neuer Name');
  });

  testWidgets('add icon follows the light and dark brand colour', (
    WidgetTester tester,
  ) async {
    for (final (ThemeMode mode, Color expected) in <(ThemeMode, Color)>[
      (ThemeMode.light, AppColors.light.primary),
      (ThemeMode.dark, AppColors.dark.primary),
    ]) {
      await pumpScreen(
        tester,
        const TodosScreen(),
        themeMode: mode,
        overrides: <Override>[
          todoStoreProvider.overrideWithValue(InMemoryTodoStore()),
        ],
      );
      await tester.pumpAndSettle();

      final Icon icon = tester.widget<Icon>(find.byIcon(AppIcons.add).first);
      expect(icon.color, expected);
    }
  });

  testWidgets('toggling an item reveals the clear-completed action', (
    WidgetTester tester,
  ) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await store.writeAll(<Todo>[
      Todo(id: '1', title: 'Aufgabe', createdAt: DateTime(2026)),
    ]);
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Erledigte entfernen'), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Erledigte entfernen'), findsOneWidget);
    expect((await store.readAll()).single.done, isTrue);
  });

  testWidgets('deleting an item returns to the empty state', (
    WidgetTester tester,
  ) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await store.writeAll(<Todo>[
      Todo(id: '1', title: 'Wegwerfen', createdAt: DateTime(2026)),
    ]);
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Wegwerfen'), findsNothing);
    expect(find.text('Keine Aufgaben'), findsOneWidget);
    expect(await store.readAll(), isEmpty);
  });

  testWidgets('clear completed removes done items only', (
    WidgetTester tester,
  ) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await store.writeAll(<Todo>[
      Todo(id: '1', title: 'Behalten', createdAt: DateTime(2026, 1, 1)),
      Todo(
        id: '2',
        title: 'Erledigt',
        done: true,
        createdAt: DateTime(2026, 1, 2),
      ),
    ]);
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Erledigte entfernen'));
    await tester.pumpAndSettle();

    expect(find.text('Erledigt'), findsNothing);
    expect(find.text('Behalten'), findsOneWidget);
  });

  testWidgets('renders English when the locale is en', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const TodosScreen(),
      locale: AppLocales.english,
      overrides: <Override>[
        todoStoreProvider.overrideWithValue(InMemoryTodoStore()),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('No tasks'), findsOneWidget);
    expect(find.text('Keine Aufgaben'), findsNothing);
  });

  testWidgets('tapping add with an empty field shows inline feedback and '
      'creates no task', (WidgetTester tester) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Bitte gib einen Aufgabentext ein.'), findsOneWidget);
    expect(find.text('Keine Aufgaben'), findsOneWidget);
    expect(await store.readAll(), isEmpty);

    final TextField field = tester.widget(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('creating a folder shows it as a filter chip', (
    WidgetTester tester,
  ) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ordner hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Uni');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Erstellen'));
    await tester.pumpAndSettle();

    expect(find.text('Uni'), findsOneWidget);
    final List<TodoFolder> folders = await store.readFolders();
    expect(folders, hasLength(1));
    expect(folders.single.name, 'Uni');
  });

  testWidgets('moving a task into a folder assigns it and the folder filter '
      'shows only that task', (WidgetTester tester) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await store.writeFolders(<TodoFolder>[
      TodoFolder(id: 'f1', name: 'Uni', createdAt: DateTime(2026)),
    ]);
    await store.writeAll(<Todo>[
      Todo(id: '1', title: 'Im Ordner', createdAt: DateTime(2026, 1, 1)),
      Todo(id: '2', title: 'Andere Aufgabe', createdAt: DateTime(2026, 1, 2)),
    ]);
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ordner ändern').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Uni'));
    await tester.pumpAndSettle();

    expect((await store.readAll()).first.folderId, 'f1');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Uni'));
    await tester.pumpAndSettle();

    expect(find.text('Im Ordner'), findsOneWidget);
    expect(find.text('Andere Aufgabe'), findsNothing);
  });

  testWidgets('deleting a non-empty folder requires an explicit choice and '
      'never drops tasks silently', (WidgetTester tester) async {
    final InMemoryTodoStore store = InMemoryTodoStore();
    await store.writeFolders(<TodoFolder>[
      TodoFolder(id: 'f1', name: 'Uni', createdAt: DateTime(2026)),
    ]);
    await store.writeAll(<Todo>[
      Todo(
        id: '1',
        title: 'Aufgabe',
        createdAt: DateTime(2026),
        folderId: 'f1',
      ),
    ]);
    await pumpScreen(
      tester,
      const TodosScreen(),
      overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.widgetWithText(ChoiceChip, 'Uni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Dieser Ordner enthält Aufgaben. Wähle, was mit ihnen passieren soll.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Aufgaben nach „Ohne Ordner“ verschieben'));
    await tester.pumpAndSettle();

    expect(await store.readFolders(), isEmpty);
    expect((await store.readAll()).single.folderId, isNull);
    expect(find.text('Aufgabe'), findsOneWidget);
  });
  // The compose field lives in `controls`, not in the body, so `ScreenScaffold`
  // renders it even while the body shows the read error. The controller refuses
  // every write in that state — correctly, because each mutation writes the
  // WHOLE list back and would otherwise overwrite tasks that are still on the
  // device. What was missing was saying so: `_submit` cleared the field before
  // calling `add()`, and `add()` returned quietly, so the typed task vanished
  // with no message, no snack bar and nothing for a screen reader.
  group('a failed read is visible at the compose field', () {
    testWidgets('adding keeps the typed text and names the reason', (
      WidgetTester tester,
    ) async {
      final _UnreadableTodoStore store = _UnreadableTodoStore(<Todo>[
        Todo(id: '1', title: 'Wichtig', createdAt: DateTime(2026)),
      ]);
      await pumpScreen(
        tester,
        const TodosScreen(),
        overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hausarbeit abgeben');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.add).first);
      await tester.pumpAndSettle();

      // The stored list is untouched — the point of the refusal.
      expect(store.writes, 0);
      expect(store.stored.single.title, 'Wichtig');

      // And the reader is told, instead of watching the text disappear.
      expect(
        find.text(
          'Nicht gespeichert: Die Aufgabenliste konnte nicht geladen werden. '
          'Deine Eingabe bleibt stehen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Hausarbeit abgeben'), findsOneWidget);
    });

    testWidgets('the message clears again as soon as the reader types', (
      WidgetTester tester,
    ) async {
      final _UnreadableTodoStore store = _UnreadableTodoStore(<Todo>[]);
      await pumpScreen(
        tester,
        const TodosScreen(),
        overrides: <Override>[todoStoreProvider.overrideWithValue(store)],
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Erster Versuch');
      await tester.tap(find.byIcon(AppIcons.add).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Nicht gespeichert'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Zweiter Versuch');
      await tester.pumpAndSettle();
      expect(find.textContaining('Nicht gespeichert'), findsNothing);
    });
  });
}

/// A store whose list cannot be read, while its contents are still there.
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

class _WriteFailingTodoStore extends InMemoryTodoStore {
  @override
  Future<void> upsertTodo(Todo todo) async =>
      throw TodoStoreFailure(TodoStoreOperation.write, StateError('failed'));
}
