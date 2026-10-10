// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';
import '../../settings/application/sign_out_everywhere_controller.dart';
import '../../settings/domain/direct_service.dart';
import '../../settings/presentation/sign_out_everywhere_tile.dart';
import '../../hsa_ki/presentation/hsa_ki_connect_flow.dart';
import '../../nextcloud/application/nextcloud_account_controller.dart';
import '../../nextcloud/domain/nextcloud_account.dart';
import '../application/university_account_controller.dart';
import '../application/university_service_connector.dart';
import 'university_account_setup_sheet.dart';

/// Settings card for the optional locally retained university identity and its
/// deliberately separate service connections.
class UniversityAccountCard extends ConsumerStatefulWidget {
  const UniversityAccountCard({super.key});

  @override
  ConsumerState<UniversityAccountCard> createState() =>
      _UniversityAccountCardState();
}

class _UniversityAccountCardState extends ConsumerState<UniversityAccountCard> {
  final Set<DirectService> _busy = <DirectService>{};
  final Map<DirectService, String> _errors = <DirectService, String>{};

  /// Services that were linked to the previous account and wait for the
  /// user's explicit `+` after an account change.
  final Set<DirectService> _awaitingConsent = <DirectService>{};

  Future<void> _showSetup({
    DirectService initialService = DirectService.mail,
  }) async {
    final UniversityServiceConnectionResult? result =
        await showUniversityAccountSetupSheet(
          context,
          initialService: initialService,
        );
    if (!mounted || result == null) return;
    final AppLocalizations l10n = context.l10n;
    setState(() {
      _errors.clear();
      _awaitingConsent
        ..clear()
        ..addAll(result.awaitingConsent);
      for (final DirectService service in result.failedReconnections) {
        _errors[service] = l10n.universityAccountReconnectFailed(
          universityServiceLabel(l10n, service),
        );
      }
    });
  }

  Future<void> _toggle(
    DirectService service, {
    required bool connected,
    required bool hasIdentity,
  }) async {
    if (_busy.contains(service)) return;
    if (service == DirectService.nextcloud) {
      await _toggleNextcloud(connected: connected);
      return;
    }
    if (service == DirectService.hsaKi && !connected) {
      await _connectHsaKi();
      return;
    }
    if (!connected && !hasIdentity) {
      await _showSetup(initialService: service);
      return;
    }

    setState(() {
      _busy.add(service);
      _errors.remove(service);
      _awaitingConsent.remove(service);
    });
    try {
      final UniversityServiceConnector connector = ref.read(
        universityServiceConnectorProvider,
      );
      if (connected) {
        await connector.disconnect(service);
      } else {
        await connector.connect(service);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors[service] = connected
            ? context.l10n.universityAccountDisconnectFailed
            : universityAccountErrorMessage(context.l10n, service, error);
      });
    } finally {
      if (mounted) setState(() => _busy.remove(service));
    }
  }

  /// HSA-GPT's `+` on this card always opens its own dedicated consent screen
  /// first — see `AGENTS.md` §2. The first-run wizard uses the same flow
  /// (`OnboardingUniversityServicesStep`). Disconnecting needs no special
  /// case and falls through to the generic path above.
  Future<void> _connectHsaKi() async {
    const DirectService service = DirectService.hsaKi;
    setState(() {
      _busy.add(service);
      _errors.remove(service);
      _awaitingConsent.remove(service);
    });
    try {
      await connectHsaKiWithOnboarding(context, ref);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors[service] = universityAccountErrorMessage(
          context.l10n,
          service,
          error,
        );
      });
    } finally {
      if (mounted) setState(() => _busy.remove(service));
    }
  }

  Future<void> _toggleNextcloud({required bool connected}) async {
    const DirectService service = DirectService.nextcloud;
    setState(() {
      _busy.add(service);
      _errors.remove(service);
      _awaitingConsent.remove(service);
    });
    try {
      final NextcloudAccountController controller = ref.read(
        nextcloudAccountControllerProvider.notifier,
      );
      if (connected) {
        await ref.read(universityServiceConnectorProvider).disconnect(service);
      } else {
        await controller.connect();
        final AsyncValue state = ref.read(nextcloudAccountControllerProvider);
        if (state.hasError) throw state.error!;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors[service] = connected
            ? context.l10n.universityAccountDisconnectFailed
            : universityAccountErrorMessage(context.l10n, service, error);
      });
    } finally {
      if (mounted) setState(() => _busy.remove(service));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<UniversityAccountState> account = ref.watch(
      universityAccountControllerProvider,
    );
    final UniversityAccountState? identity = account.value;
    final bool hasIdentity = identity?.hasIdentity ?? false;
    final bool accountUnavailable = account.isLoading || account.hasError;
    final Set<DirectService> connected = ref
        .watch(connectedDirectServicesProvider)
        .toSet();
    final AsyncValue<NextcloudAccount?> nextcloudAccount = ref.watch(
      nextcloudAccountControllerProvider,
    );

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs),
                    child: Icon(AppIcons.account_circle_outlined),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.universityAccountTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          hasIdentity
                              ? l10n.universityAccountStoredFor(
                                  identity!.identifier!,
                                )
                              : l10n.universityAccountNotStored,
                        ),
                      ],
                    ),
                  ),
                  if (account.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: SizedBox.square(
                        dimension: AppSizes.icon,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                l10n.universityAccountIntro,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (account.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.universityAccountSecureStorageError,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            for (final DirectService service in DirectService.values)
              _UniversityServiceRow(
                service: service,
                connected: connected.contains(service),
                busy:
                    _busy.contains(service) ||
                    (service == DirectService.nextcloud &&
                        nextcloudAccount.isLoading),
                notice: _awaitingConsent.contains(service)
                    ? l10n.universityAccountConnectAfterAccountChange
                    : null,
                error:
                    _errors[service] ??
                    (service == DirectService.nextcloud &&
                            nextcloudAccount.hasError
                        ? universityAccountErrorMessage(
                            l10n,
                            service,
                            nextcloudAccount.error!,
                          )
                        : null),
                onPressed: accountUnavailable
                    ? (service == DirectService.nextcloud
                          ? () => _toggle(
                              service,
                              connected: connected.contains(service),
                              hasIdentity: hasIdentity,
                            )
                          : null)
                    : () => _toggle(
                        service,
                        connected: connected.contains(service),
                        hasIdentity: hasIdentity,
                      ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: accountUnavailable ? null : _showSetup,
                  icon: Icon(
                    hasIdentity
                        ? AppIcons.edit_outlined
                        : AppIcons.add_circle_outline,
                  ),
                  label: Text(
                    hasIdentity
                        ? l10n.universityAccountUpdate
                        : l10n.universityAccountAdd,
                  ),
                ),
              ),
            ),
            const Divider(),
            const SignOutEverywhereTile(),
          ],
        ),
      ),
    );
  }
}

class _UniversityServiceRow extends StatelessWidget {
  const _UniversityServiceRow({
    required this.service,
    required this.connected,
    required this.busy,
    required this.error,
    required this.notice,
    required this.onPressed,
  });

  final DirectService service;
  final bool connected;
  final bool busy;
  final String? error;

  /// A neutral hint shown instead of the connection state, never as an error.
  final String? notice;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String label = universityServiceLabel(l10n, service);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final IconData serviceIcon = switch (service) {
      DirectService.mail => AppIcons.mail_outline,
      DirectService.moodle => AppIcons.school_outlined,
      DirectService.grades => AppIcons.grade_outlined,
      DirectService.nextcloud => AppIcons.cloud_outlined,
      DirectService.hsaKi => AppIcons.message_2,
    };
    final String actionLabel = connected
        ? l10n.universityAccountDisconnectService(label)
        : l10n.universityAccountConnectService(label);

    return ListTile(
      leading: Icon(serviceIcon),
      title: Text(label),
      subtitle: Semantics(
        liveRegion: error != null || notice != null,
        child: Text(
          error ??
              notice ??
              (connected
                  ? l10n.universityAccountConnected
                  : l10n.universityAccountDisconnected),
          style: error == null ? null : TextStyle(color: colors.error),
        ),
      ),
      trailing: busy
          ? Semantics(
              label: actionLabel,
              child: const SizedBox.square(
                dimension: AppSizes.minTouchTarget,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : IconButton(
              constraints: const BoxConstraints.tightFor(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
              ),
              onPressed: onPressed,
              tooltip: actionLabel,
              icon: Icon(
                connected
                    ? AppIcons.remove_circle_outline
                    : AppIcons.add_circle_outline,
              ),
            ),
    );
  }
}
