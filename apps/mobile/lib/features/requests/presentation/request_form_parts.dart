// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/documents/app_document.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../domain/application_files.dart';
import '../domain/request_drafts.dart';

/// Asks before a frozen draft whose key has expired is released to be sent
/// as a new case.
///
/// The one path that can genuinely produce a duplicate, so it is shared by
/// both forms and never automatic: without it, a frozen draft past the 30-day
/// window was a dead end (E-05), and the only way out was deleting it.
Future<bool> confirmResubmitAsNew(BuildContext context) async {
  final AppLocalizations l10n = context.l10n;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.requestsResubmitAsNewTitle),
      content: Text(l10n.requestsResubmitAsNewBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.requestsCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.requestsKeyExpiredSendAnyway),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shown by a form whose stored drafts could not be read.
///
/// Deliberately not an empty form: a fresh draft started here would be saved
/// over every draft still on disk.
class RequestDraftsUnavailableView extends StatelessWidget {
  const RequestDraftsUnavailableView({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return EmptyView(
      icon: AppIcons.error_outline,
      message: l10n.requestsDraftsUnavailable,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(AppIcons.refresh),
        label: Text(l10n.actionRetry),
      ),
    );
  }
}

/// A field label that says, in words, that the field is required.
///
/// An asterisk alone is a convention a screen reader announces as "star" and
/// that a first-time user has to infer. The word is in the accessible name;
/// the marker stays for people who read the form at a glance.
class RequiredLabel extends StatelessWidget {
  const RequiredLabel({required this.text, this.isRequired = true, super.key});

  final String text;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        label: isRequired ? '$text, ${l10n.requestsRequiredMark}' : text,
        excludeSemantics: true,
        child: Row(
          children: <Widget>[
            Text(text, style: Theme.of(context).textTheme.labelLarge),
            if (isRequired)
              Text(
                ' *',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: context.colors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single-select picker fed by a remote list.
///
/// Carries all four states the list can be in — loading, empty, failed with a
/// retry, and loaded — because every one of them is reachable here and an
/// empty dropdown that silently means "the request failed" is the worst of
/// them.
class PickerField<T> extends StatelessWidget {
  const PickerField({
    required this.values,
    required this.selectedId,
    required this.idOf,
    required this.nameOf,
    required this.loadingText,
    required this.emptyText,
    required this.errorText,
    required this.retryText,
    required this.onRetry,
    required this.onSelected,
    this.enabled = true,
    this.fieldError,
    super.key,
  });

  final AsyncValue<List<T>> values;
  final int? selectedId;
  final int Function(T) idOf;
  final String Function(T) nameOf;
  final String loadingText;
  final String emptyText;
  final String errorText;
  final String retryText;
  final VoidCallback onRetry;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final String? fieldError;

  @override
  Widget build(BuildContext context) {
    return switch (values) {
      AsyncLoading<List<T>>() when !values.hasValue => Row(
        children: <Widget>[
          const SizedBox(
            width: AppSizes.iconSmall,
            height: AppSizes.iconSmall,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(loadingText)),
        ],
      ),
      AsyncError<List<T>>() => _Retryable(
        message: errorText,
        action: retryText,
        onRetry: onRetry,
      ),
      _ => _dropdown(context, values.requireValue),
    };
  }

  Widget _dropdown(BuildContext context, List<T> items) {
    if (items.isEmpty) {
      return _Retryable(
        message: emptyText,
        action: retryText,
        onRetry: onRetry,
      );
    }
    // A value that is no longer in the list must not be preselected: it would
    // route the submission at a target that has gone away.
    final bool known = items.any((T item) => idOf(item) == selectedId);
    return DropdownButtonFormField<int>(
      initialValue: known ? selectedId : null,
      decoration: InputDecoration(errorText: fieldError),
      items: <DropdownMenuItem<int>>[
        for (final T item in items)
          DropdownMenuItem<int>(
            value: idOf(item),
            child: Text(nameOf(item), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled
          ? (int? value) {
              if (value != null) onSelected(value);
            }
          : null,
    );
  }
}

class _Retryable extends StatelessWidget {
  const _Retryable({
    required this.message,
    required this.action,
    required this.onRetry,
  });

  final String message;
  final String action;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.xs),
      OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(AppIcons.refresh),
        label: Text(action),
      ),
    ],
  );
}

/// One of the four named file fields.
///
/// Shows what the endpoint will accept *before* the picker opens, and what was
/// picked afterwards — name, type and size — so a wrong file is visible rather
/// than discovered on submission.
class FileSlotField extends StatelessWidget {
  const FileSlotField({
    required this.slot,
    required this.attachment,
    required this.onPick,
    required this.onRemove,
    this.enabled = true,
    this.errorText,
    super.key,
  });

  final ApplicationFileSlot slot;
  final RequestAttachment? attachment;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;
    final RequestAttachment? file = attachment;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            RequiredLabel(text: _label(l10n), isRequired: slot.isRequired),
            Text(
              l10n.requestsSlotFormats(
                slot.extensions.map((String e) => e.toUpperCase()).join(', '),
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            if (slot == ApplicationFileSlot.studentCard) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(AppIcons.lock_outline, size: AppSizes.iconSmall),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.requestsStudentCardPrivacy,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (file == null)
              OutlinedButton.icon(
                onPressed: enabled ? onPick : null,
                icon: const Icon(AppIcons.attach_file),
                label: Text(l10n.requestsSlotChoose),
              )
            else
              Row(
                children: <Widget>[
                  const Icon(AppIcons.description_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          file.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (file.sizeBytes != null)
                          Text(
                            humanFileSize(
                              file.sizeBytes!,
                              locale: Localizations.localeOf(
                                context,
                              ).languageCode,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.requestsSlotReplace,
                    onPressed: enabled ? onPick : null,
                    icon: const Icon(AppIcons.swap_horiz),
                  ),
                  IconButton(
                    // Was `requestsDeleteDraft`: a screen reader announced
                    // "delete draft" on the button that only removes one file.
                    tooltip: l10n.requestsRemoveAttachment,
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
            if (errorText != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _label(AppLocalizations l10n) => applicationSlotLabel(l10n, slot);
}

/// The visible name of a file slot.
///
/// Lifted out of `FileSlotField` so the pre-submit review can name the same
/// slots with the same words.
String applicationSlotLabel(AppLocalizations l10n, ApplicationFileSlot slot) =>
    switch (slot) {
      ApplicationFileSlot.financeRequest => l10n.requestsSlotFinanceRequest,
      ApplicationFileSlot.studentCard => l10n.requestsSlotStudentCard,
      ApplicationFileSlot.annexA => l10n.requestsSlotAnnexA,
      ApplicationFileSlot.annexB => l10n.requestsSlotAnnexB,
    };
