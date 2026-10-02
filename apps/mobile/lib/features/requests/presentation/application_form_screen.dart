// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/requests_controller.dart';
import '../application/requests_providers.dart';
import '../data/attachment_picker.dart';
import '../domain/application_files.dart';
import '../domain/application_location.dart';
import '../domain/request_drafts.dart';
import '../domain/request_gateway.dart';
import '../domain/request_validation.dart';
import 'application_review_sheet.dart';
import 'request_form_parts.dart';
import 'request_status_labels.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// The finance application form.
///
/// Field order is the endpoint's order and the paper form's order: location,
/// subject, applicant, then the four files. Nothing else is asked for — no
/// amount, no category, no contact address — because the endpoint takes none
/// of them and the numbers belong in the attached PDF.
class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({this.draftId, super.key});

  /// An existing draft to continue, or `null` to start a new one.
  final String? draftId;

  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _applicant;

  FinanceApplicationDraft? _draft;
  bool _submitting = false;
  bool _showErrors = false;

  /// Server-side issues, kept per field without displaying external wording.
  Map<RequestField, String> _serverErrors = <RequestField, String>{};
  List<String> _generalIssues = <String>[];
  String? _banner;

  /// Upload progress of the submission in flight, or null while the total is
  /// unknown.
  double? _uploadProgress;

  /// Lets the reader abandon an upload without leaving the screen.
  SubmissionCancelToken? _cancelToken;

  /// Set when the last attempt was refused because the idempotency key is
  /// older than 30 days. The only way forward from there is a deliberate new
  /// case, so the banner has to offer one.
  bool _keyExpired = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _applicant = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _title.dispose();
    _applicant.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final RequestsController controller = ref.read(requestsProvider.notifier);
    await ref.read(requestsProvider.future);
    final String? id = widget.draftId;
    final RequestDraft? existing = id == null ? null : controller.byId(id);
    final FinanceApplicationDraft draft = existing is FinanceApplicationDraft
        ? existing
        : controller.createApplication(now: DateTime.now());
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _title.text = draft.title;
      _applicant.text = draft.applicant;
    });
  }

  /// Keeps the draft on the device as the user types.
  ///
  /// Saving on every change is what makes leaving the screen safe: there is no
  /// "unsaved changes" state to lose, and a crash costs at most the last
  /// keystroke.
  /// The board's name for the review sheet, or a placeholder while the list
  /// is still loading.
  String _locationName(AppLocalizations l10n, int? id) {
    if (id == null) return l10n.requestsLocationsEmpty;
    final List<ApplicationLocation> all =
        ref.read(applicationLocationsProvider).value ??
        const <ApplicationLocation>[];
    for (final ApplicationLocation location in all) {
      if (location.id == id) return location.name;
    }
    return l10n.requestsLocationsLoading;
  }

  /// Abandons the old idempotency key and lets this draft be sent as a new
  /// case.
  ///
  /// The one path that can genuinely produce a duplicate, which is why it asks
  /// first and why it is never automatic. Before this existed, the only way
  /// out of an expired key was deleting the draft — and with it every
  /// attachment, the copy of the student ID included.
  Future<void> _resubmitAsNew() async {
    final FinanceApplicationDraft? draft = _draft;
    if (draft == null) return;
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
    if (!(confirmed ?? false) || !mounted) return;

    await ref.read(requestsProvider.notifier).unfreeze(draft.id);
    if (!mounted) return;
    setState(() {
      _banner = null;
      _keyExpired = false;
    });
    _adoptStoredDraft();
  }

  /// Re-reads this draft from the controller.
  ///
  /// The screen holds a local copy so the text fields have something stable to
  /// bind to, but the store is the truth — and `submit()` can change it under
  /// us by freezing the draft.
  void _adoptStoredDraft() {
    final FinanceApplicationDraft? current = _draft;
    if (current == null) return;
    final RequestDraft? stored = ref
        .read(requestsProvider.notifier)
        .byId(current.id);
    if (stored is FinanceApplicationDraft && stored != current) {
      setState(() => _draft = stored);
    }
  }

  Future<void> _update(
    FinanceApplicationDraft Function(FinanceApplicationDraft) change,
  ) async {
    final FinanceApplicationDraft? current = _draft;
    if (current == null) return;
    if (current.isFrozen) {
      // Reachable if the freeze happened between build and keystroke. Saying
      // so beats dropping the input without a word.
      _showMessage(context.l10n.requestsFrozenEditBlocked);
      return;
    }
    final FinanceApplicationDraft next = change(current);
    setState(() => _draft = next);
    await ref.read(requestsProvider.notifier).save(next, now: DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final FinanceApplicationDraft? draft = _draft;

    return ScreenScaffold(
      title: l10n.requestsApplicationFormTitle,
      body: draft == null ? const LoadingView() : _form(context, l10n, draft),
    );
  }

  Widget _form(
    BuildContext context,
    AppLocalizations l10n,
    FinanceApplicationDraft draft,
  ) {
    final RequestValidation validation = RequestValidation.validate(draft);
    final AsyncValue<List<ApplicationLocation>> locations = ref.watch(
      applicationLocationsProvider,
    );

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
        if (draft.isFrozen) ...<Widget>[
          StatusBanner(
            tone: StatusTone.warning,
            icon: AppIcons.hourglass_top_outlined,
            title: l10n.requestsFrozenTitle,
            message: l10n.requestsFrozenBody,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        // Rendered whenever there is either a message OR issues. Gating it on
        // the message alone meant an endpoint that returned issues for fields
        // this form does not know, with an empty message, produced a submit
        // that appeared to do nothing at all.
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

        // 1 — Standort
        RequiredLabel(text: l10n.requestsFieldLocation),
        PickerField<ApplicationLocation>(
          values: locations,
          selectedId: draft.locationId,
          idOf: (ApplicationLocation l) => l.id,
          nameOf: (ApplicationLocation l) => l.name,
          loadingText: l10n.requestsLocationsLoading,
          emptyText: l10n.requestsLocationsEmpty,
          errorText: l10n.requestsLocationsUnavailable,
          retryText: l10n.requestsStatusRetry,
          enabled: !draft.isFrozen,
          onRetry: () => ref.invalidate(applicationLocationsProvider),
          onSelected: (int id) => _update(
            (FinanceApplicationDraft d) => d.copyWith(locationId: id),
          ),
          fieldError: errorFor(RequestField.location),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 2 — Antragsgegenstand
        RequiredLabel(text: l10n.requestsFieldTitle),
        TextField(
          controller: _title,
          enabled: !draft.isFrozen,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          // Enforced in the field itself, so the limit is a fact rather than a
          // message that arrives after the work is done.
          maxLength: FinanceApplicationDraft.textMaxLength,
          decoration: InputDecoration(
            hintText: l10n.requestsFieldTitleHint,
            errorText: errorFor(RequestField.title),
          ),
          onChanged: (String value) =>
              _update((FinanceApplicationDraft d) => d.copyWith(title: value)),
        ),
        const SizedBox(height: AppSpacing.md),

        // 3 — Antragsteller
        RequiredLabel(text: l10n.requestsFieldApplicant),
        TextField(
          controller: _applicant,
          enabled: !draft.isFrozen,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: FinanceApplicationDraft.textMaxLength,
          decoration: InputDecoration(
            hintText: l10n.requestsFieldApplicantHint,
            errorText: errorFor(RequestField.applicant),
          ),
          onChanged: (String value) => _update(
            (FinanceApplicationDraft d) => d.copyWith(applicant: value),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 4–7 — die vier Dateifelder in Formularreihenfolge
        for (final ApplicationFileSlot slot
            in kApplicationSlotOrder) ...<Widget>[
          FileSlotField(
            slot: slot,
            attachment: draft.fileFor(slot),
            enabled: !draft.isFrozen,
            errorText: errorFor(RequestField.forSlot(slot)),
            onPick: () => _pick(slot),
            onRemove: () => _removeFile(slot),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        const SizedBox(height: AppSpacing.lg),
        if (_submitting) ...<Widget>[
          // A determinate bar wherever the total is known, and a way out.
          // Killing the app instead is what produces the unclear outcome in
          // REQ-1, so an explicit cancel is the gentler exit — it freezes the
          // draft under the same key rather than risking a second case.
          LinearProgressIndicator(value: _uploadProgress),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _cancelToken?.cancel(),
              child: Text(l10n.requestsCancelUpload),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: AppSizes.iconSmall,
                  height: AppSizes.iconSmall,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(AppIcons.send_outlined),
          label: Text(
            _submitting
                ? l10n.requestsSubmitting
                : l10n.requestsSubmitApplication,
          ),
        ),
      ],
    );
  }

  Future<void> _pick(ApplicationFileSlot slot) async {
    final AppLocalizations l10n = context.l10n;
    final PickResult result = await ref
        .read(attachmentPickerProvider)
        .pickFor(
          slot,
          currentTotalBytes:
              _draft?.files.entries
                  .where(
                    (MapEntry<ApplicationFileSlot, RequestAttachment> entry) =>
                        entry.key != slot,
                  )
                  .fold<int>(
                    0,
                    (int total, entry) => total + (entry.value.sizeBytes ?? 0),
                  ) ??
              0,
        );
    if (!mounted) return;

    switch (result) {
      case PickedFile(:final RequestAttachment attachment):
        final RequestAttachment? previous = _draft?.fileFor(slot);
        await _update(
          (FinanceApplicationDraft d) => d.withFile(slot, attachment),
        );
        // Replace means the old copy is no longer referenced by anything.
        if (previous != null) {
          await ref.read(attachmentStoreProvider).delete(previous);
        }
      case PickCancelled():
        return;
      case PickWrongType():
        _showMessage(l10n.requestsSlotWrongType);
      case PickTooLarge():
        _showMessage(l10n.requestsSlotTooLarge);
      case PickFailed():
        // Not `requestsSubmitFailed`: nothing was submitted, and saying so
        // sends the reader looking for a case that does not exist.
        _showMessage(l10n.requestsPickFailed);
    }
  }

  Future<void> _removeFile(ApplicationFileSlot slot) async {
    final RequestAttachment? existing = _draft?.fileFor(slot);
    await _update((FinanceApplicationDraft d) => d.withFile(slot, null));
    if (existing != null) {
      await ref.read(attachmentStoreProvider).delete(existing);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    final FinanceApplicationDraft? draft = _draft;
    if (draft == null) return;

    final AppLocalizations l10n = context.l10n;
    setState(() {
      _showErrors = true;
      _serverErrors = <RequestField, String>{};
      _generalIssues = <String>[];
      _banner = null;
      _keyExpired = false;
    });

    if (!RequestValidation.validate(draft).isValid) return;

    // A last look before the point of no return — but only on a FIRST send.
    // A frozen draft is being replayed byte-for-byte under the same key, so
    // there is nothing left to review and asking again would just be a second
    // barrier in front of the one recovery path that exists.
    if (!draft.isFrozen) {
      final bool confirmed = await showApplicationReviewSheet(
        context,
        draft: draft,
        locationName: _locationName(l10n, draft.locationId),
      );
      if (!confirmed || !mounted) return;
    }

    // Guards against a double tap producing two submissions.
    final SubmissionCancelToken cancel = SubmissionCancelToken();
    setState(() {
      _submitting = true;
      _uploadProgress = null;
      _cancelToken = cancel;
    });
    final SubmitOutcome outcome = await ref
        .read(requestsProvider.notifier)
        .submit(
          draft,
          now: DateTime.now(),
          // Up to four documents of 25 MB each: on mobile data the button
          // spinner alone left the app looking hung for minutes.
          onProgress: (int sent, int total) {
            if (!mounted || total <= 0) return;
            setState(() => _uploadProgress = sent / total);
          },
          cancel: cancel,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _uploadProgress = null;
      _cancelToken = null;
    });
    // The controller may have frozen this draft. Until the screen adopts that,
    // it kept showing an editable form over a draft the store had already
    // locked: typing was silently discarded by `save()`, and pressing send
    // again replayed the LOCAL un-frozen copy — which skips the fingerprint
    // and 30-day checks and lands in the 409 conflict that the freeze exists
    // to prevent.
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
      case SubmitKeyExpired():
        setState(() {
          _banner = l10n.requestsKeyExpiredBody;
          _keyExpired = true;
        });
      case SubmitPayloadChanged():
        setState(() => _banner = l10n.requestsPayloadChanged);
      case SubmitGatewaySaid(:final SubmissionResult result):
        _applyGatewayResult(l10n, result);
    }
  }

  /// Puts rejected fields where they belong using app-localized wording.
  ///
  /// Nothing the user typed or picked is touched here — a rejected submission
  /// leaves the form exactly as it was, which is the whole point.
  void _applyGatewayResult(AppLocalizations l10n, SubmissionResult result) {
    if (result is SubmissionRejected) {
      setState(() {
        _serverErrors = <RequestField, String>{
          for (final RequestField field in result.fieldErrors.keys)
            field: l10n.requestsErrorRejectedField,
        };
        _generalIssues = <String>[l10n.requestsSubmitRejectedHint];
        _banner = l10n.requestsSubmitRejected;
      });
      return;
    }
    setState(() => _banner = RequestLabels.submissionProblem(l10n, result));
  }
}
