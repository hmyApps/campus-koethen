// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/case_status_controller.dart';
import '../application/requests_controller.dart';
import '../application/requests_providers.dart';
import '../application/submissions_controller.dart';
import '../domain/case_status.dart';
import '../domain/request_drafts.dart';
import '../domain/submitted_case.dart';
import 'request_status_labels.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// „Anträge & Feedback“: the two things you can start, what you have sent, and
/// what you have not finished writing.
///
/// Submissions come first among the lists: a student who opens this screen is
/// far more often checking on something than starting something new.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh on open. The status endpoint answers `no-store`, so what the
    // list shows has to be fetched rather than remembered.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatuses());
  }

  Future<void> _refreshStatuses() async {
    // Awaited: on the first frame the stored cases are still loading, and an
    // empty read here would leave the list showing nothing but spinners.
    final List<SubmittedCase> cases;
    try {
      cases = await ref.read(submissionsProvider.future);
    } catch (_) {
      // Unreadable: the section shows the error and its retry instead.
      return;
    }
    if (!mounted || cases.isEmpty) return;
    await ref
        .read(caseStatusProvider.notifier)
        .refreshAll(cases, now: DateTime.now());
  }

  Future<void> _refresh() async {
    ref.invalidate(submissionsProvider);
    await _refreshStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool connected = ref.watch(requestsEndpointConfiguredProvider);
    // Watched as AsyncValues rather than flattened with `.value ?? []`: the
    // status link is the ONLY way back into a case, so "still loading" and
    // "could not be read" must never be rendered as "you have none". That
    // reading invites a second submission of an application that already
    // exists — with the copy of the student ID attached to it.
    final AsyncValue<List<SubmittedCase>> caseState = ref.watch(
      submissionsProvider,
    );
    final AsyncValue<List<RequestDraft>> draftState = ref.watch(
      requestsProvider,
    );
    final List<SubmittedCase> cases =
        caseState.value ?? const <SubmittedCase>[];
    final List<RequestDraft> drafts =
        draftState.value ?? const <RequestDraft>[];

    return ScreenScaffold(
      eyebrow: ModuleCategory.campus.label(l10n),
      title: l10n.requestsTitle,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(context.metrics.screenPadding),
          children: <Widget>[
            if (!connected) ...<Widget>[
              StatusBanner(
                tone: StatusTone.warning,
                icon: AppIcons.cloud_off_outlined,
                title: l10n.requestsNotConnectedTitle,
                message: l10n.requestsNotConnectedBody,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            _StartAction(
              icon: AppIcons.file_euro,
              title: l10n.requestsActionApplication,
              subtitle: l10n.requestsActionApplicationHint,
              onTap: () => context.pushNamed(AppRoutes.requestApplicationName),
            ),
            const SizedBox(height: AppSpacing.sm),
            _StartAction(
              icon: AppIcons.message_2,
              title: l10n.requestsActionFeedback,
              subtitle: l10n.requestsActionFeedbackHint,
              onTap: () => context.pushNamed(AppRoutes.requestFeedbackName),
            ),

            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(title: l10n.requestsSubmissions),
            if (caseState.isLoading && !caseState.hasValue)
              const _SectionLoading()
            else if (caseState.hasError && !caseState.hasValue)
              _SectionError(onRetry: () => ref.invalidate(submissionsProvider))
            else if (cases.isEmpty)
              _EmptyLine(text: l10n.requestsNoSubmissions)
            else
              for (final SubmittedCase item in cases)
                _SubmissionTile(submitted: item),

            const SizedBox(height: AppSpacing.xl),
            _SectionHeader(title: l10n.requestsDrafts),
            if (draftState.isLoading && !draftState.hasValue)
              const _SectionLoading()
            else if (draftState.hasError && !draftState.hasValue)
              _SectionError(onRetry: () => ref.invalidate(requestsProvider))
            else if (drafts.isEmpty)
              _EmptyLine(text: l10n.requestsNoDrafts)
            else
              for (final RequestDraft draft in drafts) _DraftTile(draft: draft),
          ],
        ),
      ),
    );
  }
}

class _StartAction extends StatelessWidget {
  const _StartAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: context.colors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(AppIcons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
    ),
  );
}

/// One submitted case: what it is, what it is called, and where it stands.
///
/// The status line is whatever is currently known — loading, an error with a
/// retry, or the committee's own column name. Nothing here is read from a
/// stored copy of an earlier answer.
class _SubmissionTile extends ConsumerWidget {
  const _SubmissionTile({required this.submitted});

  final SubmittedCase submitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final CaseStatusState status = ref.watch(
      caseStatusProvider.select(
        (Map<String, CaseStatusState> all) =>
            all[submitted.id] ?? const CaseStatusState(),
      ),
    );

    final CaseStatus? loaded = status.status;
    final String title = switch (loaded) {
      ApplicationCaseStatus(:final String title) when title.isNotEmpty => title,
      FeedbackCaseStatus(:final String text) when text.isNotEmpty => text,
      _ => submitted.localTitle,
    };
    final String number = submitted.number ?? loaded?.number ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        isThreeLine: true,
        leading: Icon(
          submitted.kind == RequestKind.financeApplication
              ? AppIcons.request_page_outlined
              : AppIcons.forum_outlined,
        ),
        title: Text(
          title.isEmpty ? RequestLabels.kind(l10n, submitted.kind) : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              <String>[
                RequestLabels.kind(l10n, submitted.kind),
                if (number.isNotEmpty) l10n.requestsNumberLabel(number),
              ].join(' · '),
            ),
            _StatusLine(id: submitted.id, state: status),
            Text(
              l10n.requestsSubmittedAt(
                AppDateFormats.dateTime(submitted.submittedAt, locale),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (loaded != null)
              Text(
                l10n.requestsUpdatedAt(
                  AppDateFormats.dateTime(loaded.updatedAt, locale),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        onTap: () => context.pushNamed(
          AppRoutes.requestSubmissionName,
          pathParameters: <String, String>{'id': submitted.id},
        ),
      ),
    );
  }
}

/// The one line that says where a case stands right now.
class _StatusLine extends ConsumerWidget {
  const _StatusLine({required this.id, required this.state});

  final String id;
  final CaseStatusState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = context.colors;

    if (state.isLoading && !state.hasStatus) {
      return Text(
        l10n.requestsStatusLoading,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
      );
    }

    final CaseStatus? status = state.status;
    if (status != null) {
      final bool archived = status is ApplicationCaseStatus && status.archived;
      return Row(
        children: <Widget>[
          Icon(
            archived ? AppIcons.task_alt : AppIcons.timelapse_outlined,
            size: AppSizes.iconSmall,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              archived
                  ? '${RequestLabels.statusName(l10n, status.statusName)} · '
                        '${l10n.requestsArchivedLabel}'
                  : RequestLabels.statusName(l10n, status.statusName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    final String? problem = state.error == null
        ? null
        : RequestLabels.statusProblem(l10n, state.error!);
    return Text(
      problem ?? l10n.requestsStatusLoading,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
    );
  }
}

class _DraftTile extends ConsumerWidget {
  const _DraftTile({required this.draft});

  final RequestDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;

    final String title = switch (draft) {
      FinanceApplicationDraft(:final String title) => title,
      FeedbackDraft(:final String feedback) => feedback,
    };
    // VE-N02: a draft whose upload is still running (the form may have been
    // left meanwhile) says so and cannot be deleted from under it.
    final bool inFlight = ref
        .watch(requestsInFlightProvider)
        .contains(draft.id);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(
          inFlight
              ? AppIcons.send_outlined
              : draft.isFrozen
              ? AppIcons.hourglass_top_outlined
              : AppIcons.edit_note_outlined,
        ),
        title: Text(
          title.trim().isEmpty
              ? RequestLabels.kind(l10n, draft.kind)
              : title.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          inFlight
              ? l10n.requestsSubmitting
              : draft.isFrozen
              ? l10n.requestsFrozenTitle
              : AppDateFormats.dateTime(draft.updatedAt, locale),
        ),
        trailing: IconButton(
          tooltip: l10n.requestsDeleteDraft,
          icon: const Icon(AppIcons.delete_outline),
          onPressed: inFlight ? null : () => _confirmDelete(context, ref, l10n),
        ),
        onTap: () => switch (draft) {
          FinanceApplicationDraft() => context.pushNamed(
            AppRoutes.requestApplicationName,
            queryParameters: <String, String>{'draft': draft.id},
          ),
          FeedbackDraft() => context.pushNamed(
            AppRoutes.requestFeedbackName,
            queryParameters: <String, String>{'draft': draft.id},
          ),
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        // A frozen draft holds the idempotency key. Deleting it throws away
        // the only thing that would recognise a case that already arrived, so
        // that consequence is spelled out rather than left to the same
        // one-line dialog an ordinary draft gets.
        content: Text(
          draft.isFrozen
              ? '${l10n.requestsDeleteConfirm}\n\n'
                    '${l10n.requestsDeleteFrozenWarning}'
              : l10n.requestsDeleteConfirm,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.requestsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.requestsDeleteDraft),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(requestsProvider.notifier).delete(draft.id);
    }
  }
}

/// A section that is still being read from the encrypted store.
class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: <Widget>[
        const SizedBox(
          height: AppSizes.iconSmall,
          width: AppSizes.iconSmall,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          context.l10n.commonLoading,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

/// A section whose store could not be read.
///
/// Deliberately not an empty line: "no cases" and "we could not open the box
/// your cases live in" mean opposite things to someone deciding whether to
/// submit again.
class _SectionError extends StatelessWidget {
  const _SectionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: StatusBanner(
        tone: StatusTone.warning,
        icon: AppIcons.error_outline,
        title: l10n.requestsLoadFailedTitle,
        action: TextButton(
          onPressed: onRetry,
          child: Text(l10n.requestsStatusRetry),
        ),
      ),
    );
  }
}
