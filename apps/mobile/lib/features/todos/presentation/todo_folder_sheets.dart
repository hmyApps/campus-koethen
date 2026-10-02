// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/todo_folders_controller.dart';
import '../application/todos_controller.dart';
import '../domain/todo.dart';
import '../domain/todo_folder.dart';
import '../domain/todo_store.dart';

/// Opens the "move to folder" picker for [todo] as a modal sheet.
Future<void> showTodoFolderPicker(
  BuildContext context,
  WidgetRef ref,
  Todo todo,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext _) => _TodoFolderPickerSheet(todo: todo),
  );
}

class _TodoFolderPickerSheet extends ConsumerWidget {
  const _TodoFolderPickerSheet({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final List<TodoFolder> folders =
        ref.watch(todoFoldersControllerProvider).value ?? const <TodoFolder>[];

    Future<void> select(String? folderId) async {
      final bool committed = await _runTodoWrite(
        context,
        () => ref
            .read(todosControllerProvider.notifier)
            .moveToFolder(todo.id, folderId),
      );
      if (committed && context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.todoMoveToFolderTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(AppIcons.inbox_outlined),
                    title: Text(l10n.todoFolderUnfiledLabel),
                    trailing: todo.folderId == null
                        ? const Icon(AppIcons.check)
                        : null,
                    selected: todo.folderId == null,
                    onTap: () => select(null),
                  ),
                  for (final TodoFolder folder in folders)
                    ListTile(
                      leading: const Icon(AppIcons.folder_outlined),
                      title: Text(folder.name),
                      trailing: todo.folderId == folder.id
                          ? const Icon(AppIcons.check)
                          : null,
                      selected: todo.folderId == folder.id,
                      onTap: () => select(folder.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a dialog to create a new folder.
Future<void> showCreateTodoFolderDialog(BuildContext context, WidgetRef ref) =>
    _showTodoFolderNameDialog(
      context: context,
      title: (AppLocalizations l10n) => l10n.todoFolderCreateTitle,
      confirmLabel: (AppLocalizations l10n) => l10n.todoFolderCreateAction,
      initialName: '',
      onConfirm: (String name) =>
          ref.read(todoFoldersControllerProvider.notifier).create(name),
    );

/// Opens a dialog to rename an existing folder.
Future<void> showRenameTodoFolderDialog(
  BuildContext context,
  WidgetRef ref,
  TodoFolder folder,
) => _showTodoFolderNameDialog(
  context: context,
  title: (AppLocalizations l10n) => l10n.todoFolderRenameTitle,
  confirmLabel: (AppLocalizations l10n) => l10n.todoFolderRenameAction,
  initialName: folder.name,
  onConfirm: (String name) =>
      ref.read(todoFoldersControllerProvider.notifier).rename(folder.id, name),
);

Future<void> _showTodoFolderNameDialog({
  required BuildContext context,
  required String Function(AppLocalizations) title,
  required String Function(AppLocalizations) confirmLabel,
  required String initialName,
  required Future<void> Function(String name) onConfirm,
}) async {
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _TodoFolderNameDialog(
      title: title(dialogContext.l10n),
      confirmLabel: confirmLabel(dialogContext.l10n),
      initialName: initialName,
    ),
  );
  if (!context.mounted) return;
  if (name != null && name.trim().isNotEmpty) {
    await _runTodoWrite(context, () => onConfirm(name));
  }
}

/// The name-entry dialog for creating/renaming a folder. Owns its
/// [TextEditingController] so it is disposed exactly when this dialog is,
/// never earlier than a still-animating close transition can use it.
class _TodoFolderNameDialog extends StatefulWidget {
  const _TodoFolderNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
  });

  final String title;
  final String confirmLabel;
  final String initialName;

  @override
  State<_TodoFolderNameDialog> createState() => _TodoFolderNameDialogState();
}

class _TodoFolderNameDialogState extends State<_TodoFolderNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
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
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: l10n.todoFolderNameHint),
        onSubmitted: (String value) {
          if (value.trim().isEmpty) return;
          Navigator.of(context).pop(value);
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (BuildContext _, TextEditingValue value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(value.text),
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}

/// Opens the options sheet (rename / delete) for [folder].
Future<void> showTodoFolderOptionsSheet(
  BuildContext context,
  WidgetRef ref,
  TodoFolder folder,
) {
  final AppLocalizations l10n = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.todoFolderOptionsTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(AppIcons.edit_outlined),
            title: Text(l10n.todoFolderRenameAction),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await showRenameTodoFolderDialog(context, ref, folder);
            },
          ),
          ListTile(
            leading: const Icon(AppIcons.delete_outline),
            title: Text(l10n.todoFolderDeleteAction),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await _confirmAndDeleteTodoFolder(context, ref, folder);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmAndDeleteTodoFolder(
  BuildContext context,
  WidgetRef ref,
  TodoFolder folder,
) async {
  final AppLocalizations l10n = context.l10n;
  final List<Todo> items =
      ref.read(todosControllerProvider).value ?? const <Todo>[];
  final bool hasTasks = items.any((Todo t) => t.folderId == folder.id);

  if (!hasTasks) {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.todoFolderDeleteConfirmTitle),
            content: Text(l10n.todoFolderDeleteEmptyMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.todoFolderDeleteAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (!context.mounted) return;
    await _runTodoWrite(
      context,
      () => ref
          .read(todoFoldersControllerProvider.notifier)
          .delete(folder.id, TodoFolderDeleteAction.moveToUnfiled),
    );
    return;
  }

  final TodoFolderDeleteAction? action =
      await showDialog<TodoFolderDeleteAction>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.todoFolderDeleteConfirmTitle),
          content: Text(l10n.todoFolderDeleteNonEmptyMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(TodoFolderDeleteAction.deleteTasks),
              child: Text(l10n.todoFolderDeleteRemoveTasksAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(TodoFolderDeleteAction.moveToUnfiled),
              child: Text(l10n.todoFolderDeleteMoveAction),
            ),
          ],
        ),
      );
  if (action == null) return;
  if (!context.mounted) return;
  await _runTodoWrite(
    context,
    () => ref
        .read(todoFoldersControllerProvider.notifier)
        .delete(folder.id, action),
  );
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
