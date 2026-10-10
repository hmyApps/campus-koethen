// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/requests_controller.dart';
import '../application/requests_providers.dart';
import '../domain/feedback_area.dart';
import '../domain/request_drafts.dart';
import '../domain/request_gateway.dart';
import '../domain/request_validation.dart';
import 'request_form_parts.dart';
import 'request_status_labels.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// The feedback form: area, an optional name, and the text.
///
/// No title field — the receiving system derives the card title from the text
/// itself — and no attachments, because the endpoint takes none.
class FeedbackFormScreen extends ConsumerStatefulWidget {
  const FeedbackFormScreen({this.draftId, super.key});

  final String? draftId;

  @override
  ConsumerState<FeedbackFormScreen> createState() => _FeedbackFormScreenState();
}

class _FeedbackFormScreenState extends ConsumerState<FeedbackFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _text;

  FeedbackDraft? _draft;
  bool _loadFailed = false;
  bool _submitting = false;
  bool _showErrors = false;

  Map<RequestField, String> _serverErrors = <RequestField, String>{};
  List<String> _generalIssues = <String>[];
  String? _banner;

  /// Set when the last attempt was refused because the idempotency key is
  /// older than 30 days; the banner then offers a deliberate new case (E-05).
  bool _keyExpired = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _text = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final RequestsController controller = ref.read(requestsProvider.notifier);
    try {
      await ref.read(requestsProvider.future);
    } catch (_) {
      // Unreadable drafts are not "no drafts" — see the application form.
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
    final String? id = widget.draftId;
    final RequestDraft? existing = id == null ? null : controller.byId(id);
    final FeedbackDraft draft = existing is FeedbackDraft
        ? existing
        : controller.createFeedback(now: DateTime.now());
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _name.text = draft.submitterName;
      _text.text = draft.feedback;
    });
  }

  /// Re-reads this draft from the controller.
  ///
  /// The store is the truth; the local copy only exists so the text fields
  /// have something stable to bind to. `submit()` can freeze the stored draft
  /// under us.
  /// Abandons the old idempotency key and lets this feedback be sent as a new
  /// case — after asking, never on its own. See the application form.
  Future<void> _resubmitAsNew() async {
    final FeedbackDraft? draft = _draft;
    if (draft == null) return;
    if (!await confirmResubmitAsNew(context) || !mounted) return;

    await ref.read(requestsProvider.notifier).unfreeze(draft.id);
    if (!mounted) return;
    setState(() {
      _banner = null;
      _keyExpired = false;
    });
    _adoptStoredDraft();
  }

  void _adoptStoredDraft() {
    final FeedbackDraft? current = _draft;
    if (current == null) return;
    final RequestDraft? stored = ref
        .read(requestsProvider.notifier)
        .byId(current.id);
    if (stored is FeedbackDraft && stored != current) {
      setState(() => _draft = stored);
    }
  }

  /// True while this draft is being sent, from here or from another copy of
  /// this form (E-01, VE-N02).
  bool _isBusy(RequestDraft draft) =>
      _submitting || ref.read(requestsInFlightProvider).contains(draft.id);

  /// Another copy of this form finished sending this draft: take over what
  /// the store now holds, or leave if the draft became a submitted case.
  void _adoptAfterForeignFlight() {
    final FeedbackDraft? current = _draft;
    if (current == null || _submitting || !mounted) return;
    final RequestDraft? stored = ref
        .read(requestsProvider.notifier)
        .byId(current.id);
    if (stored is FeedbackDraft) {
      setState(() => _draft = stored);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _update(FeedbackDraft Function(FeedbackDraft) change) async {
    final FeedbackDraft? current = _draft;
    if (current == null) return;
    // What is on the wire must not change under it.
    if (_isBusy(current)) return;
    if (current.isFrozen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.requestsFrozenEditBlocked)),
        );
      }
      return;
    }
    final FeedbackDraft next = change(current);
    setState(() => _draft = next);
    await ref.read(requestsProvider.notifier).save(next, now: DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final FeedbackDraft? draft = _draft;
    ref.listen<Set<String>>(requestsInFlightProvider, (
      Set<String>? previous,
      Set<String> next,
    ) {
      final String? id = _draft?.id;
      if (id == null) return;
      if ((previous?.contains(id) ?? false) && !next.contains(id)) {
        _adoptAfterForeignFlight();
      }
    });

    return ScreenScaffold(
      title: l10n.requestsFeedbackFormTitle,
      body: draft != null
          ? _form(context, l10n, draft)
          : _loadFailed
          ? RequestDraftsUnavailableView(onRetry: _retryLoad)
          : const LoadingView(),
    );
  }

  void _retryLoad() {
    setState(() => _loadFailed = false);
    ref.invalidate(requestsProvider);
    _load();
  }

  Widget _form(
    BuildContext context,
    AppLocalizations l10n,
    FeedbackDraft draft,
  ) {
    final RequestValidation validation = RequestValidation.validate(draft);
    final AsyncValue<List<FeedbackArea>> areas = ref.watch(
      feedbackAreasProvider,
    );
    // E-01 / VE-N02: locked while this draft is on the wire, here or from a
    // second copy of the form.
    final bool inFlight = ref
        .watch(requestsInFlightProvider)
        .contains(draft.id);
    final bool busy = _submitting || inFlight;
    final bool locked = draft.isFrozen || busy;

    String? errorFor(RequestField field) {
      final String? server = _serverErrors[field];
      if (server != null && server.isNotEmpty) return server;
      if (!_showErrors) return null;
      final RequestFieldError? local = validation.errorFor(field);
      return local == null ? null : RequestLabels.fieldError(l10n, local);
    }

    return ListView(
      padding: EdgeInsets.all(context.metrics.screenPadding),
      children: <Widget>[
        // The same warning the list screen shows. Without it the whole form —
        // including the upload of a student ID — could be filled in before
        // anything revealed that this build has no endpoint to send to.
        if (!ref.watch(requestsEndpointConfiguredProvider)) ...<Widget>[
          StatusBanner(
            tone: StatusTone.warning,
            icon: AppIcons.cloud_off_outlined,
            title: l10n.requestsNotConnectedTitle,
            message: l10n.requestsNotConnectedBody,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (inFlight && !_submitting) ...<Widget>[
          StatusBanner(
            tone: StatusTone.info,
            icon: AppIcons.hourglass_top_outlined,
            title: l10n.requestsSubmitting,
            message: l10n.requestsSubmitInFlightBody,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (draft.isFrozen) ...<Widget>[
          StatusBanner(
            tone: StatusTone.warning,
            icon: AppIcons.hourglass_top_outlined,
            title: l10n.requestsFrozenTitle,
            message: l10n.requestsFrozenBody,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        // Either a message or issues is enough to show the banner: gated on
        // the message alone, issues about fields this form does not know
        // vanished silently.
        if (_banner != null || _generalIssues.isNotEmpty) ...<Widget>[
          StatusBanner(
            tone: StatusTone.warning,
            icon: AppIcons.error_outline,
            title: _banner ?? l10n.requestsIssuesTitle,
            message: _generalIssues.join('\n'),
            action: _keyExpired
                ? TextButton(
                    onPressed: _resubmitAsNew,
                    child: Text(l10n.requestsKeyExpiredSendAnyway),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 1 — Bereich
        RequiredLabel(text: l10n.requestsFieldArea),
        PickerField<FeedbackArea>(
          values: areas,
          selectedId: draft.areaId,
          idOf: (FeedbackArea a) => a.id,
          nameOf: (FeedbackArea a) => a.name,
          loadingText: l10n.requestsAreasLoading,
          emptyText: l10n.requestsAreasEmpty,
          errorText: l10n.requestsAreasUnavailable,
          retryText: l10n.requestsStatusRetry,
          enabled: !locked,
          onRetry: () => ref.invalidate(feedbackAreasProvider),
          onSelected: (int id) =>
              _update((FeedbackDraft d) => d.copyWith(areaId: id)),
          fieldError: errorFor(RequestField.area),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 2 — Dein Name (optional)
        RequiredLabel(text: l10n.requestsFieldSubmitterName, isRequired: false),
        TextField(
          controller: _name,
          enabled: !locked,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: FeedbackDraft.nameMaxLength,
          decoration: InputDecoration(
            hintText: l10n.requestsFieldSubmitterNameHint,
            errorText: errorFor(RequestField.submitterName),
          ),
          onChanged: (String value) =>
              _update((FeedbackDraft d) => d.copyWith(submitterName: value)),
        ),
        Text(
          l10n.requestsSubmitterNameNote,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 3 — Dein Feedback
        RequiredLabel(text: l10n.requestsFieldFeedback),
        TextField(
          controller: _text,
          enabled: !locked,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          minLines: 7,
          maxLines: null,
          maxLength: FeedbackDraft.textMaxLength,
          decoration: InputDecoration(
            hintText: l10n.requestsFieldFeedbackHint,
            helperText: l10n.requestsFeedbackCounter,
            errorText: errorFor(RequestField.feedback),
            alignLabelWithHint: true,
          ),
          onChanged: (String value) =>
              _update((FeedbackDraft d) => d.copyWith(feedback: value)),
        ),

        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: busy ? null : _submit,
          icon: busy
              ? const SizedBox(
                  width: AppSizes.iconSmall,
                  height: AppSizes.iconSmall,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(AppIcons.send_outlined),
          label: Text(
            busy ? l10n.requestsSubmitting : l10n.requestsSubmitFeedback,
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final FeedbackDraft? draft = _draft;
    if (draft == null || _isBusy(draft)) return;

    final AppLocalizations l10n = context.l10n;
    setState(() {
      _showErrors = true;
      _serverErrors = <RequestField, String>{};
      _generalIssues = <String>[];
      _banner = null;
      _keyExpired = false;
    });

    if (!RequestValidation.validate(draft).isValid) return;

    setState(() => _submitting = true);
    final SubmitOutcome outcome;
    try {
      outcome = await ref
          .read(requestsProvider.notifier)
          .submit(draft, now: DateTime.now());
    } finally {
      // E-04: whatever happened, the spinner must not outlive the attempt.
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    // The controller may have frozen this draft; the local copy has to follow
    // or the form stays editable over a draft the store has already locked.
    _adoptStoredDraft();

    switch (outcome) {
      case SubmitRecorded(:final submitted):
        context.pushReplacementNamed(
          AppRoutes.requestSubmissionName,
          pathParameters: <String, String>{'id': submitted.id},
          extra: true,
        );
      case SubmitStoreFailed():
        setState(() => _banner = l10n.requestsSubmitStoreFailed);
      case SubmitStoreUnavailable():
        setState(() => _banner = l10n.requestsSubmitStoreUnavailable);
      case SubmitInFlight():
        setState(() => _banner = l10n.requestsSubmitInFlightBody);
      case SubmitDraftStoreFailed():
        setState(() => _banner = l10n.requestsSubmitDraftStoreFailed);
      case SubmitKeyExpired():
        setState(() {
          _banner = l10n.requestsKeyExpiredBody;
          _keyExpired = true;
        });
      case SubmitPayloadChanged():
        setState(() => _banner = l10n.requestsPayloadChanged);
      case SubmitGatewaySaid(:final SubmissionResult result):
        if (result is SubmissionRejected) {
          setState(() {
            // Localised throughout: raw endpoint text never reaches the UI.
            // That also settles the swallowed-issues half of REQ-2 — the
            // banner is now always set, so a rejection can no longer look
            // like a submit that did nothing.
            _serverErrors = <RequestField, String>{
              for (final RequestField field in result.fieldErrors.keys)
                field: l10n.requestsErrorRejectedField,
            };
            _generalIssues = <String>[l10n.requestsSubmitRejectedHint];
            _banner = l10n.requestsSubmitRejected;
          });
        } else {
          setState(
            () => _banner = RequestLabels.submissionProblem(l10n, result),
          );
        }
    }
  }
}
