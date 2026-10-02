// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/documents/app_document.dart';
import '../../../core/documents/document_viewer_screen.dart';
import '../../../core/links/safe_link_launcher.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/case_status_controller.dart';
import '../application/requests_providers.dart';
import '../application/submissions_controller.dart';
import '../data/case_document_downloader.dart';
import '../domain/case_status.dart';
import '../domain/request_drafts.dart';
import '../domain/status_gateway.dart';
import '../domain/submitted_case.dart';
import 'request_status_labels.dart';
import 'submission_polling_controller.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// Everything the public API says about one case, rendered natively.
///
/// The route carries the **local** id and nothing else. The status link, the
/// receipt link and every document link are bearer credentials: they stay in
/// encrypted storage and never appear in an app route, a query parameter, a
/// deep link or on screen. The status link is handed to the external browser
/// only after the reader selects "Zum Antrag" and only after an exact-origin
/// check against `REQUESTS_BASE_URL`.
///
/// While this screen is open and the app is in the foreground it refreshes
/// about once a minute. It stops the moment the screen goes away or the app is
/// backgrounded — there is no unbounded background service — and a 429 pauses
/// it for exactly as long as the server asked.
class SubmissionDetailScreen extends ConsumerStatefulWidget {
  const SubmissionDetailScreen({
    required this.submissionId,
    this.justSubmitted = false,
    super.key,
  });

  final String submissionId;

  /// True when this screen was opened by a submission that just succeeded.
  ///
  /// There was no success moment at all before: the form simply replaced
  /// itself with a status page, and the one fact that matters most — that the
  /// link to this case exists nowhere but on this device — was left to the
  /// small print further down.
  final bool justSubmitted;

  @override
  ConsumerState<SubmissionDetailScreen> createState() =>
      _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState extends ConsumerState<SubmissionDetailScreen>
    with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(seconds: 60);

  late final SubmissionPollingController _polling;
  bool _loadingDocument = false;

  /// URL of the document currently being fetched, so the spinner appears on
  /// the tile that was actually tapped rather than on all of them.
  String? _loadingDocumentUrl;

  @override
  void initState() {
    super.initState();
    _polling = SubmissionPollingController(
      interval: _pollInterval,
      onPoll: _refresh,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _startPolling();
    });
  }

  @override
  void dispose() {
    // Leaving the screen stops the polling immediately.
    _polling.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _startPolling();
    } else {
      _polling.stop();
    }
  }

  void _startPolling() {
    _polling.start();
  }

  Future<void> _refresh() async {
    // Awaited, not read: on the first frame the stored cases are still being
    // loaded, and reading the empty state would silently skip the refresh the
    // screen exists for.
    final List<SubmittedCase> cases = await ref.read(
      submissionsProvider.future,
    );
    if (!mounted) return;
    final SubmittedCase? item = cases
        .where((SubmittedCase c) => c.id == widget.submissionId)
        .firstOrNull;
    if (item == null) return;
    final StatusResult result = await ref
        .read(caseStatusProvider.notifier)
        .refresh(item, now: DateTime.now());
    // The server's own instruction wins: while rate limited, stop asking.
    if (result is StatusRateLimited && mounted) {
      final Duration wait = result.retryAfter ?? const Duration(minutes: 1);
      _polling.pauseFor(wait);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<SubmittedCase> cases =
        ref.watch(submissionsProvider).value ?? const <SubmittedCase>[];
    final SubmittedCase? item = cases
        .where((SubmittedCase c) => c.id == widget.submissionId)
        .firstOrNull;

    if (item == null) {
      return ScreenScaffold(
        title: l10n.requestsTitle,
        body: EmptyView(
          icon: AppIcons.inbox_outlined,
          title: l10n.requestsNoSubmissions,
          message: l10n.requestsStatusNotFound,
        ),
      );
    }

    final CaseStatusState status = ref.watch(
      caseStatusProvider.select(
        (Map<String, CaseStatusState> all) =>
            all[item.id] ?? const CaseStatusState(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(RequestLabels.kind(l10n, item.kind)),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.requestsRefresh,
            onPressed: _refresh,
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(context.metrics.screenPadding),
          children: _body(context, l10n, item, status),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AppLocalizations l10n,
    SubmittedCase item,
    CaseStatusState state,
  ) {
    final String locale = Localizations.localeOf(context).languageCode;
    final CaseStatus? status = state.status;
    final String caseUrl = status?.statusUrl ?? item.statusUrl;

    return <Widget>[
      if (widget.justSubmitted) ...<Widget>[
        StatusBanner(
          tone: StatusTone.positive,
          icon: AppIcons.check_circle_outline,
          title: l10n.requestsSuccessTitle,
          message: l10n.requestsSuccessOnlyOnThisDevice,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (item.wasReplay) ...<Widget>[
        StatusBanner(icon: AppIcons.done_all, title: l10n.requestsReplayNotice),
        const SizedBox(height: AppSpacing.md),
      ],

      _Headline(
        // Feedback has no title of its own: the committee derives the card
        // title from the text, and the full text is shown below — repeating a
        // truncated copy at the top would say the same thing worse.
        title: switch (status) {
          ApplicationCaseStatus(:final String title) => title,
          FeedbackCaseStatus() => '',
          _ => item.kind == RequestKind.feedback ? '' : item.localTitle,
        },
        number: item.number ?? status?.number,
      ),
      const SizedBox(height: AppSpacing.md),

      _StatusCard(state: state, onRetry: _refresh),
      const SizedBox(height: AppSpacing.md),

      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(AppIcons.link_outlined),
          title: Text(l10n.requestsOpenCase),
          subtitle: Text(l10n.requestsOpenCaseHint),
          trailing: const Icon(AppIcons.open_in_new),
          onTap: () => _openCase(caseUrl),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // Times: what the device recorded, and what the server last changed.
      _Line(
        icon: AppIcons.outbox_outlined,
        text: l10n.requestsSubmittedAt(
          AppDateFormats.dateTime(
            status?.submittedAt ?? item.submittedAt,
            locale,
          ),
        ),
      ),
      if (status != null)
        _Line(
          icon: AppIcons.update,
          text: l10n.requestsUpdatedAt(
            AppDateFormats.dateTime(status.updatedAt, locale),
          ),
        ),
      if (status is ApplicationCaseStatus && status.resubmittedAt != null)
        _Line(
          icon: AppIcons.reply_outlined,
          text: l10n.requestsResubmittedAt(
            AppDateFormats.dateTime(status.resubmittedAt!, locale),
          ),
        ),

      if (status is ApplicationCaseStatus && status.applicant != null) ...[
        const SizedBox(height: AppSpacing.md),
        _Labelled(label: l10n.requestsApplicantLabel, value: status.applicant!),
      ],

      if (status is FeedbackCaseStatus) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        _Labelled(label: l10n.requestsFeedbackAreaLabel, value: status.area),
        const SizedBox(height: AppSpacing.sm),
        _Labelled(
          label: l10n.requestsFeedbackSubmitterLabel,
          value: status.submitterName,
        ),
        const SizedBox(height: AppSpacing.sm),
        // The complete text, never truncated — it is what the user wrote.
        _Labelled(label: l10n.requestsFeedbackTextLabel, value: status.text),
      ],

      if (status?.publicNote != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        StatusBanner(
          icon: AppIcons.campaign_outlined,
          title: l10n.requestsPublicNote,
          message: status!.publicNote!,
        ),
      ],

      const SizedBox(height: AppSpacing.lg),
      _SectionTitle(text: l10n.requestsDocuments),
      // The receipt is always available: its link came back with the
      // submission itself. Sharing is off — the PDF carries the same token.
      _DocumentTile(
        label: l10n.requestsReceipt,
        icon: AppIcons.receipt_long_outlined,
        onOpen: () => _openDocument(
          url: item.receiptPdfUrl,
          // Hardcoded German before: this string is the viewer's visible
          // title, so it belongs in the string table like every other one.
          filename: l10n.requestsReceiptFilename,
          mimeType: 'application/pdf',
        ),
        enabled: item.receiptPdfUrl.isNotEmpty && !_loadingDocument,
        loading: _loadingDocumentUrl == item.receiptPdfUrl,
      ),
      if (status != null)
        if (status.documents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.requestsNoDocuments,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          for (final StatusDocument document in status.documents)
            _DocumentTile(
              label: document.label,
              icon: AppIcons.description_outlined,
              enabled: !_loadingDocument,
              loading: _loadingDocumentUrl == document.downloadUrl,
              onOpen: () => _openDocument(
                url: document.downloadUrl,
                filename: document.filename,
                mimeType: document.mimeType,
              ),
            ),

      if (status != null) ...<Widget>[
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(text: l10n.requestsActionsTitle),
        _Line(
          icon: AppIcons.upload_file_outlined,
          text: RequestLabels.actions(
            l10n,
            submitMode: status.actions.submitMode,
          ),
        ),
        if (status.actions.canUploadDocuments)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              // Honest about the boundary: the public API has no upload
              // endpoint for this, so the app does not pretend to have one.
              l10n.requestsActionsWebOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],

      const SizedBox(height: AppSpacing.lg),
      Text(
        l10n.requestsSecretLinkNotice,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.md),
      OutlinedButton.icon(
        onPressed: () => _confirmForget(l10n, item),
        icon: const Icon(AppIcons.delete_outline),
        label: Text(l10n.requestsForgetCase),
      ),
    ];
  }

  Future<void> _openCase(String url) async {
    final AppLocalizations l10n = context.l10n;
    // The link is a bearer credential. HTTPS alone is not enough: it may only
    // leave the app for the exact origin configured for this build.
    if (ref.read(requestsOriginProvider)?.allows(url) != true) {
      _message(l10n.requestsStatusLinkInvalid);
      return;
    }

    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(url);
    if (!mounted) return;
    if (result != LinkLaunchResult.opened) {
      _message(l10n.requestsOpenCaseUnavailable);
    }
  }

  /// Downloads one document and shows it in the shared in-app viewer.
  ///
  /// Sharing is disabled for everything here: each of these files is reachable
  /// only through a token that is equivalent to the case's password.
  Future<void> _openDocument({
    required String url,
    required String filename,
    required String mimeType,
  }) async {
    final AppLocalizations l10n = context.l10n;
    setState(() {
      _loadingDocument = true;
      _loadingDocumentUrl = url;
    });
    final DocumentResult result = await ref
        .read(caseDocumentDownloaderProvider)
        .fetch(url: url, filename: filename, mimeType: mimeType);
    if (!mounted) return;
    setState(() {
      _loadingDocument = false;
      _loadingDocumentUrl = null;
    });

    switch (result) {
      case DocumentLoaded(:final AppDocument document):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) =>
                DocumentViewerScreen(document: document, allowSharing: false),
          ),
        );
      case DocumentRefused():
        _message(l10n.requestsDocumentRefused);
      case DocumentTooLarge():
        _message(l10n.requestsDocumentTooLarge);
      case DocumentUnavailable():
        _message(l10n.requestsDocumentUnavailable);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmForget(AppLocalizations l10n, SubmittedCase item) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.requestsForgetCase),
        content: Text(l10n.requestsForgetCaseConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.requestsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.requestsForgetCaseAction),
          ),
        ],
      ),
    );
    if (!(yes ?? false)) return;
    await ref.read(submissionsProvider.notifier).remove(item.id);
    ref.read(caseStatusProvider.notifier).forget(item.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.title, required this.number});

  final String title;
  final String? number;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.trim().isNotEmpty)
          Semantics(
            header: true,
            child: Text(
              title.trim(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          (number ?? '').trim().isEmpty
              ? l10n.requestsNoNumber
              : l10n.requestsNumberLabel(number!),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

/// The current state, or why it is not known right now.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.onRetry});

  final CaseStatusState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final CaseStatus? status = state.status;

    if (status == null) {
      // `error == null` here means no attempt has failed — so on the very
      // first frame, before the initial fetch has even started, the card used
      // to claim "no current status, you appear to be offline". The only
      // truthful reading of "nothing yet, nothing failed" is "loading".
      if (state.isLoading || state.error == null) {
        return Row(
          children: <Widget>[
            const SizedBox(
              width: AppSizes.iconSmall,
              height: AppSizes.iconSmall,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(l10n.requestsStatusLoading)),
          ],
        );
      }
      final StatusResult? error = state.error;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            error == null
                ? l10n.requestsStatusOffline
                : RequestLabels.statusProblem(l10n, error) ??
                      l10n.requestsStatusUnavailable,
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.requestsStatusRetry),
          ),
        ],
      );
    }

    final bool archived = status is ApplicationCaseStatus && status.archived;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(archived ? AppIcons.task_alt : AppIcons.timelapse_outlined),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    RequestLabels.statusName(l10n, status.statusName),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (archived) Text(l10n.requestsArchivedLabel),
                  if (state.isLoading)
                    Text(
                      l10n.requestsStatusLoading,
                      style: Theme.of(context).textTheme.bodySmall,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppSizes.iconSmall),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: AppSpacing.xxs),
      SelectableText(value),
    ],
  );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.label,
    required this.icon,
    required this.onOpen,
    required this.enabled,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onOpen;
  final bool enabled;

  /// True while THIS document is being fetched.
  ///
  /// The tiles used to go quietly grey and nothing else, which on a slow
  /// connection is indistinguishable from a tap that did not register.
  final bool loading;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: ListTile(
      leading: loading
          ? const SizedBox(
              width: AppSizes.icon,
              height: AppSizes.icon,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            )
          : Icon(icon),
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: loading
          ? Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.requestsDocumentLoading,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : null,
      trailing: const Icon(AppIcons.open_in_new),
      onTap: enabled ? onOpen : null,
    ),
  );
}
