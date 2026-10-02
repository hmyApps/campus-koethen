// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/todo_folders_controller.dart';
import '../application/todos_controller.dart';
import '../domain/todo.dart';
import '../domain/todo_folder.dart';
import '../domain/todo_store.dart';
import 'todo_folder_sheets.dart';

/// Sentinel filter value for "show items without a folder", distinct from
/// `null` (which means "show everything"). Never collides with a generated
/// folder id, which always starts with a decimal timestamp.
const String _unfiledFilterId = '\u0000todo-unfiled';

/// The local to-do list at `/more/todos`.
///
/// Entirely on-device: there is no network layer and no backend behind it.
/// Tasks and their folders are read from and written to a local Hive box
/// through [todosControllerProvider] and [todoFoldersControllerProvider].
class TodosScreen extends ConsumerStatefulWidget {
  const TodosScreen({super.key});

  @override
  ConsumerState<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends ConsumerState<TodosScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// The message under the compose field, or null when there is nothing to say.
  ///
  /// Holds the message rather than a flag because there are now two reasons the
  /// field can refuse: a blank title, and a task list that could not be read
  /// (writing over it would destroy what is still on the device).
  String? _inputError;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _input.addListener(_clearErrorWhenTyping);
  }

  @override
  void dispose() {
    _input.removeListener(_clearErrorWhenTyping);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clearErrorWhenTyping() {
    if (_inputError != null && _input.text.trim().isNotEmpty) {
      setState(() => _inputError = null);
    }
  }

  Future<void> _submit() async {
    final String text = _input.text;
    if (text.trim().isEmpty) {
      _refuse(context.l10n.todoAddEmptyError);
      return;
    }
    setState(() => _inputError = null);

    // The field is NOT cleared up front any more. A failed read blocks every
    // write, and clearing first threw the typed task away silently while the
    // body was still showing the read error next to a retry button.
    bool added;
    try {
      added = await ref.read(todosControllerProvider.notifier).add(text);
    } on TodoStoreFailure {
      if (!mounted) return;
      _refuse(context.l10n.todoSaveFailedError);
      return;
    }
    if (!mounted) return;
    if (!added) {
      _refuse(context.l10n.todoAddUnavailableError);
      return;
    }
    _input.clear();
    _focus.requestFocus();
  }

  /// Keeps the typed text, says why it was not accepted, and says it out loud.
  void _refuse(String message) {
    setState(() => _inputError = message);
    _focus.requestFocus();
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<Todo>> todos = ref.watch(todosControllerProvider);
    final List<TodoFolder> folders =
        ref.watch(todoFoldersControllerProvider).value ?? const <TodoFolder>[];
    final bool hasCompleted = todos.value?.any((Todo t) => t.done) ?? false;

    // The filter can point at a folder that was just deleted; fall back to
    // "show everything" instead of rendering a chip row with nothing selected.
    final String? filter =
        _filter == null ||
            _filter == _unfiledFilterId ||
            folders.any((TodoFolder f) => f.id == _filter)
        ? _filter
        : null;

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.todosTitle,
      actions: <Widget>[
        if (hasCompleted)
          IconButton(
            tooltip: l10n.todoClearCompleted,
            icon: const Icon(AppIcons.remove_done),
            onPressed: () => _clearCompleted(l10n),
          ),
      ],
      // Writing a task is the reason the screen exists, so the field is pinned
      // under the masthead rather than hiding behind a floating button.
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _InputBar(
            controller: _input,
            focusNode: _focus,
            onSubmit: _submit,
            errorText: _inputError,
          ),
          _FolderChipRow(folders: folders, selected: filter, onSelect: _select),
        ],
      ),
      body: todos.when(
        loading: () => const LoadingView(),
        // Rendering a read failure as the ordinary empty state was the more
        // dangerous half of the same bug the controller now guards: it invited
        // the reader to type a new task over a list that is still on the
        // device but could not be opened.
        error: (Object error, _) => ErrorView(
          failure: error,
          onRetry: () => ref.invalidate(todosControllerProvider),
        ),
        data: (List<Todo> items) => _body(l10n, items, filter),
      ),
    );
  }

  void _select(String? filter) => setState(() => _filter = filter);

  /// Deletes a task and offers to put it back.
  ///
  /// The bin sits directly beside the folder icon, so a mis-tap used to delete
  /// a task outright with nothing to undo it. An undo snack bar is the
  /// lightest correction that does not put a dialog in front of the common,
  /// deliberate case.
  Future<void> _deleteTodo(AppLocalizations l10n, Todo todo) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TodosController controller = ref.read(
      todosControllerProvider.notifier,
    );
    final int index = (ref.read(todosControllerProvider).value ?? <Todo>[])
        .indexWhere((Todo t) => t.id == todo.id);
    final bool committed = await _runTodoWrite(
      context,
      () => controller.remove(todo.id),
    );
    if (!committed) return;
    if (!mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.todoDeletedUndo),
        action: SnackBarAction(
          label: l10n.todoUndo,
          onPressed: () async {
            await _runTodoWrite(
              context,
              () => controller.restore(todo, index: index < 0 ? 0 : index),
            );
          },
        ),
      ),
    );
  }

  /// Removes every completed task, with the same way back.
  Future<void> _clearCompleted(AppLocalizations l10n) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TodosController controller = ref.read(
      todosControllerProvider.notifier,
    );
    final List<Todo> before =
        ref.read(todosControllerProvider).value ?? <Todo>[];
    final List<({Todo todo, int index})> removed = <({Todo todo, int index})>[
      for (int i = 0; i < before.length; i++)
        if (before[i].done) (todo: before[i], index: i),
    ];
    if (removed.isEmpty) return;

    final bool committed = await _runTodoWrite(
      context,
      controller.clearCompleted,
    );
    if (!committed) return;
    if (!mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.todoCompletedCleared),
        action: SnackBarAction(
          label: l10n.todoUndo,
          onPressed: () async {
            await _runTodoWrite(context, () => controller.restoreAll(removed));
          },
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, List<Todo> items, String? filter) {
    if (items.isEmpty) return _EmptyTodos(l10n: l10n);
    final List<Todo> visible = switch (filter) {
      null => items,
      _unfiledFilterId =>
        items.where((Todo t) => t.folderId == null).toList(growable: false),
      final String folderId =>
        items.where((Todo t) => t.folderId == folderId).toList(growable: false),
    };
    if (visible.isEmpty) {
      return EmptyView(
        icon: AppIcons.checklist_outlined,
        title: l10n.todoEmptyTitle,
        message: l10n.todoFolderEmptyMessage,
      );
    }
    return _TodoList(
      items: visible,
      onDelete: (Todo todo) => _deleteTodo(l10n, todo),
    );
  }
}

/// The "add a task" row pinned above the list.
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.metrics.screenPadding,
        AppSpacing.md,
        context.metrics.screenPadding,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: l10n.todoAddHint,
                errorText: errorText,
                isDense: true,
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: l10n.todoAdd,
            icon: Icon(AppIcons.add, color: context.colors.primary),
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

/// Filter row: "all", the default "no folder" area, every folder, and an
/// action to create a new one. Long-pressing a folder opens rename/delete.
class _FolderChipRow extends ConsumerWidget {
  const _FolderChipRow({
    required this.folders,
    required this.selected,
    required this.onSelect,
  });

  final List<TodoFolder> folders;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return SizedBox(
      height: AppSizes.minTouchTarget + AppSpacing.md,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: context.metrics.screenPadding,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(l10n.todoFolderAllLabel),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(l10n.todoFolderUnfiledLabel),
              selected: selected == _unfiledFilterId,
              onSelected: (_) => onSelect(_unfiledFilterId),
            ),
          ),
          for (final TodoFolder folder in folders)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              // A long press was the ONLY route to renaming or deleting a
              // folder: undiscoverable by eye, and genuinely unreachable with
              // a screen reader or switch control, which do not synthesise
              // one. The same sheet is now a named custom action as well, so
              // the gesture stays for those who know it and stops being the
              // only way in.
              child: Semantics(
                customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
                  CustomSemanticsAction(label: l10n.todoFolderOptions): () =>
                      showTodoFolderOptionsSheet(context, ref, folder),
                },
                child: GestureDetector(
                  onLongPress: () =>
                      showTodoFolderOptionsSheet(context, ref, folder),
                  child: ChoiceChip(
                    label: Text(folder.name),
                    selected: selected == folder.id,
                    onSelected: (_) => onSelect(folder.id),
                  ),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(AppIcons.add, size: AppSizes.iconSmall),
            label: Text(l10n.todoFolderAddTooltip),
            onPressed: () => showCreateTodoFolderDialog(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Empty state: no tasks yet, with a reminder that the list is local-only.
class _EmptyTodos extends StatelessWidget {
  const _EmptyTodos({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: AppIcons.checklist_outlined,
      title: l10n.todoEmptyTitle,
      message: l10n.todoEmptyMessage,
    );
  }
}

/// The scrollable list of to-do items.
class _TodoList extends ConsumerWidget {
  const _TodoList({required this.items, required this.onDelete});

  final List<Todo> items;

  /// Deletion goes back through the screen, which owns the undo snack bar.
  final ValueChanged<Todo> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final TodosController controller = ref.read(
      todosControllerProvider.notifier,
    );
    final List<TodoFolder> folders =
        ref.watch(todoFoldersControllerProvider).value ?? const <TodoFolder>[];
    final Map<String, String> folderNames = <String, String>{
      for (final TodoFolder f in folders) f.id: f.name,
    };

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final Todo todo = items[index];
        final String? folder = todo.folderId == null
            ? null
            : folderNames[todo.folderId];
        return CheckboxListTile(
          key: ValueKey<String>(todo.id),
          value: todo.done,
          onChanged: (_) async {
            await _runTodoWrite(context, () => controller.toggle(todo.id));
          },
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            todo.title,
            style: todo.done
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: colors.textSecondary,
                  )
                : null,
          ),
          subtitle: folder == null
              ? null
              : Text(folder, style: TextStyle(color: colors.textSecondary)),
          secondary: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: l10n.todoRename,
                icon: const Icon(AppIcons.edit_outlined),
                onPressed: () => _renameTodo(context, controller, todo),
              ),
              IconButton(
                tooltip: l10n.todoMoveToFolder,
                icon: const Icon(AppIcons.folder_outlined),
                onPressed: () => showTodoFolderPicker(context, ref, todo),
              ),
              IconButton(
                tooltip: l10n.todoDelete,
                icon: const Icon(AppIcons.delete_outline),
                onPressed: () => onDelete(todo),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Renames a task.
///
/// `TodosController.rename` was implemented and had no caller anywhere in
/// `lib/`, so a typo could only be fixed by deleting the task and typing it
/// again.
Future<void> _renameTodo(
  BuildContext context,
  TodosController controller,
  Todo todo,
) async {
  final String? next = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => _TodoRenameDialog(todo.title),
  );
  if (next == null || next.trim().isEmpty) return;
  if (!context.mounted) return;
  await _runTodoWrite(context, () => controller.rename(todo.id, next));
}

Future<bool> _runTodoWrite(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
    return true;
  } on TodoStoreFailure {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.todoSaveFailedError)));
    }
    return false;
  }
}

/// Owns the text controller for exactly as long as the dialog is mounted.
///
/// A dialog route completes its future before its closing transition has
/// finished. Disposing a controller immediately after [showDialog] therefore
/// leaves the still-mounted [TextField] with an invalid controller.
class _TodoRenameDialog extends StatefulWidget {
  const _TodoRenameDialog(this.initialTitle);

  final String initialTitle;

  @override
  State<_TodoRenameDialog> createState() => _TodoRenameDialogState();
}

class _TodoRenameDialogState extends State<_TodoRenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.todoRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.todoFolderRenameAction),
        ),
      ],
    );
  }
}
