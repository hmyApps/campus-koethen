// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../app/app_routes.dart';
import '../../../core/documents/app_document.dart';
import '../../../core/documents/document_viewer_screen.dart';
import '../../../core/locale/formatters.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../../grades/application/grade_account_controller.dart';
import '../../grades/domain/grade_portal.dart';
import '../../grades/presentation/grade_messages.dart';
import '../../document_wallet/domain/wallet_document.dart';
import '../../document_wallet/presentation/wallet_save_action.dart';
import '../application/student_service_controller.dart';
import '../domain/student_service_gateway.dart';
import '../domain/student_service_overview.dart';
import 'student_service_messages.dart';

/// Entry point of the read-only HISinOne student-service area.
///
/// A pure gate, same shape as `GradesScreen`/`TimetableScreen`: this feature
/// has no sign-in of its own, so what it shows depends entirely on the
/// grades connection — not connected, connected to the wrong portal (HIS-QIS
/// has none of these pages), or connected to HISinOne and ready to sync.
class StudentServiceScreen extends ConsumerWidget {
  const StudentServiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<GradeAccountState> account = ref.watch(
      gradeAccountControllerProvider,
    );

    return ScreenScaffold(
      eyebrow: ModuleCategory.study.label(l10n),
      title: l10n.studentServiceTitle,
      body: account.when(
        loading: () => const LoadingView(),
        error: (Object error, _) => EmptyView(
          icon: AppIcons.error_outline,
          title: l10n.studentServiceLoadFailedTitle,
          message:
              '${l10n.studentServiceLoadFailedBody} '
              '${gradeFailureMessage(l10n, error)}',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(gradeAccountControllerProvider),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.actionRetry),
          ),
        ),
        data: (GradeAccountState state) {
          if (!state.isSignedIn) {
            return EmptyView(
              icon: AppIcons.badge_outlined,
              title: l10n.studentServiceNotConnectedTitle,
              message: l10n.studentServiceNotConnectedMessage,
              action: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.grades),
                icon: const Icon(AppIcons.grade_outlined),
                label: Text(l10n.studentServiceGoToGrades),
              ),
            );
          }
          if (state.activePortal != GradePortal.hisInOne) {
            return EmptyView(
              icon: AppIcons.badge_outlined,
              title: l10n.studentServiceWrongPortalTitle,
              message: l10n.studentServiceWrongPortalMessage,
            );
          }
          return const _StudentServiceContent();
        },
      ),
    );
  }
}

/// Appends the fixed, non-sensitive diagnostic stage (if any) so a real
/// portal mismatch can be reported with the exact failing check instead of
/// just "the portal changed".
String _withDiagnosticHint(
  AppLocalizations l10n,
  String message,
  Object? error,
) {
  final String? stage = studentServiceDiagnosticStage(error);
  if (stage == null) return message;
  return '$message ${l10n.studentServiceDiagnosticHint(stage)}';
}

class _StudentServiceContent extends ConsumerStatefulWidget {
  const _StudentServiceContent();

  @override
  ConsumerState<_StudentServiceContent> createState() =>
      _StudentServiceContentState();
}

class _StudentServiceContentState
    extends ConsumerState<_StudentServiceContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(studentServiceControllerProvider.notifier).maybeAutoSync();
      }
    });
  }

  Future<void> _refresh() =>
      ref.read(studentServiceControllerProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final AsyncValue<StudentServiceViewState> view = ref.watch(
      studentServiceControllerProvider,
    );
    final StudentServiceViewState? state = view.value;

    if (state == null) {
      return view.hasError
          ? EmptyView(
              icon: AppIcons.error_outline,
              title: l10n.studentServiceLoadFailedTitle,
              message: _withDiagnosticHint(
                l10n,
                studentServiceFailureMessage(l10n, view.error),
                view.error,
              ),
              action: FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(studentServiceControllerProvider),
                icon: const Icon(AppIcons.refresh),
                label: Text(l10n.actionRetry),
              ),
            )
          : const LoadingView();
    }

    final StudentServiceOverview? overview = state.overview;
    if (overview == null) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: StatusBanner(
                  tone: StatusTone.warning,
                  icon: AppIcons.sync_problem,
                  title: l10n.studentServiceLoadFailedTitle,
                  message: _withDiagnosticHint(
                    l10n,
                    studentServiceFailureMessage(l10n, state.error),
                    state.error,
                  ),
                  action: TextButton.icon(
                    onPressed: state.isSyncing ? null : _refresh,
                    icon: const Icon(AppIcons.refresh),
                    label: Text(l10n.actionRetry),
                  ),
                ),
              )
            else if (state.isSyncing)
              const LoadingView()
            else
              // Neither syncing nor errored, with nothing cached: the
              // 24h auto-sync throttle can leave exactly this state after
              // an earlier attempt failed and the in-memory error from
              // that attempt is gone (app restart, provider recreated).
              // A spinner with no escape hatch would then spin forever —
              // always offer a manual way to load instead.
              EmptyView(
                icon: AppIcons.sync,
                title: l10n.studentServiceNeverSynced,
                message: l10n.studentServiceNotYetLoadedMessage,
                action: FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(AppIcons.refresh),
                  label: Text(l10n.actionRefresh),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          if (state.error != null) ...<Widget>[
            StatusBanner(
              tone: StatusTone.warning,
              icon: AppIcons.sync_problem,
              title: l10n.studentServiceRefreshFailed,
              message: studentServiceFailureMessage(l10n, state.error),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            state.lastSuccessfulSync == null
                ? l10n.studentServiceNeverSynced
                : l10n.studentServiceLastSyncAt(
                    AppDateFormats.dateTime(state.lastSuccessfulSync!, locale),
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Certificates are why most readers open this screen at all —
          // shown first, ahead of the personal-data sections nobody came
          // here to re-read.
          _Section(
            title: l10n.studentServiceCertificatesHeading,
            child: overview.certificates.isEmpty
                ? Text(l10n.studentServiceNoCertificates)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final CertificateOffer offer
                          in overview.certificates)
                        _CertificateRow(offer: offer),
                    ],
                  ),
          ),
          _Section(
            title: l10n.studentServicePersonalDataHeading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final PersonalDataField field in overview.personalData)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(field.label)),
                        Expanded(
                          child: Text(field.value, textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: l10n.studentServiceContactDataHeading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final ContactTile tile in overview.contactTiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          tile.heading,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        for (final String line in tile.lines) Text(line),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: l10n.studentServiceProgrammesHeading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final ProgrammeEntry programme in overview.programmes)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      '${programme.subject} · ${programme.subjectSemester}',
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: l10n.studentServicePaymentHintHeading,
            child: Text(_paymentHintText(l10n, overview.paymentHint)),
          ),
        ],
      ),
    );
  }

  String _paymentHintText(AppLocalizations l10n, PaymentHint hint) =>
      switch (hint.kind) {
        PaymentHintKind.noneOpen => l10n.studentServicePaymentHintNoneOpen,
        PaymentHintKind.open => l10n.studentServicePaymentHintOpen(
          hint.openItemCount ?? 0,
        ),
        PaymentHintKind.unrecognised =>
          l10n.studentServicePaymentHintUnrecognised,
      };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    ),
  );
}

class _CertificateRow extends ConsumerStatefulWidget {
  const _CertificateRow({required this.offer});

  final CertificateOffer offer;

  @override
  ConsumerState<_CertificateRow> createState() => _CertificateRowState();
}

class _CertificateRowState extends ConsumerState<_CertificateRow> {
  bool _busy = false;
  String? _error;

  Future<void> _generate() async {
    final NavigatorState navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final CertificateDownloadResult result = await ref
          .read(studentServiceControllerProvider.notifier)
          .downloadCertificate(widget.offer);
      if (!mounted) return;
      final AppLocalizations l10n = context.l10n;
      switch (result) {
        case CertificateDownloadLoaded(:final bytes, :final filename):
          final AppDocument document = AppDocument(
            filename: filename,
            mediaType: 'application/pdf',
            bytes: bytes,
            sizeBytes: bytes.length,
          );
          final WalletDocumentKind? walletKind = walletKindForCertificateLabel(
            widget.offer.name,
          );
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => DocumentViewerScreen(
                document: document,
                actions: walletKind == null
                    ? const <Widget>[]
                    : <Widget>[
                        WalletSaveAction(kind: walletKind, document: document),
                      ],
              ),
            ),
          );
        case CertificateTooLarge():
          setState(() => _error = l10n.studentServiceErrorDocumentTooLarge);
        case CertificateUnavailable(:final reason):
          // `reason` is a short, fixed technical label (never a URL, token
          // or portal HTML) — safe to show so a real failure can be
          // reported with the exact cause instead of just "didn't work".
          setState(
            () => _error =
                '${l10n.studentServiceErrorDocumentUnavailable} '
                '${l10n.studentServiceDiagnosticHint(reason)}',
          );
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = _withDiagnosticHint(
          context.l10n,
          studentServiceFailureMessage(context.l10n, error),
          error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.offer.name),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _busy
                ? const SizedBox.square(
                    dimension: AppSizes.icon,
                    child: CircularProgressIndicator(
                      strokeWidth: AppSizes.rule,
                    ),
                  )
                : TextButton(
                    onPressed: _generate,
                    child: Text(l10n.studentServiceGenerateCertificate),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
