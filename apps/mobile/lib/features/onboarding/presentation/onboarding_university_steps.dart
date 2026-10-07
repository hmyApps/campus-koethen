// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/panel.dart';
import '../../../l10n/l10n.dart';
import '../../settings/application/sign_out_everywhere_controller.dart';
import '../../settings/domain/direct_service.dart';
import '../../nextcloud/application/nextcloud_account_controller.dart';
import '../../nextcloud/domain/nextcloud_account.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../../university_account/domain/university_identity.dart';
import '../../university_account/presentation/university_account_setup_sheet.dart';

/// Collects one credential draft without persisting it.
///
/// The draft stays in the owning onboarding widget's memory. Persistence only
/// happens on the following step after at least one selected university
/// service has positively validated it through [UniversityServiceConnector].
class OnboardingUniversityAccessStep extends ConsumerStatefulWidget {
  const OnboardingUniversityAccessStep({
    required this.identifier,
    required this.password,
    required this.consent,
    required this.onIdentifierChanged,
    required this.onPasswordChanged,
    required this.onConsentChanged,
    super.key,
  });

  final String identifier;
  final String password;
  final bool consent;
  final ValueChanged<String> onIdentifierChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<bool> onConsentChanged;

  @override
  ConsumerState<OnboardingUniversityAccessStep> createState() =>
      _OnboardingUniversityAccessStepState();
}

class _OnboardingUniversityAccessStepState
    extends ConsumerState<OnboardingUniversityAccessStep> {
  late final TextEditingController _identifier;
  late final TextEditingController _password;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _identifier = TextEditingController(text: widget.identifier);
    _password = TextEditingController(text: widget.password);
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<UniversityAccountState> account = ref.watch(
      universityAccountControllerProvider,
    );
    final UniversityAccountState? stored = account.value;
    if (stored?.hasIdentity ?? false) {
      return Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(AppIcons.check_circle_outline),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(l10n.universityAccountStoredFor(stored!.identifier!)),
            ),
          ],
        ),
      );
    }

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('onboarding-university-identifier'),
            controller: _identifier,
            enabled: !account.isLoading,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[
              AutofillHints.username,
              AutofillHints.email,
            ],
            decoration: InputDecoration(
              labelText: l10n.universityAccountIdentifierLabel,
              prefixIcon: const Icon(AppIcons.person_outline),
            ),
            onChanged: widget.onIdentifierChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey<String>('onboarding-university-password'),
            controller: _password,
            enabled: !account.isLoading,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.password],
            decoration: InputDecoration(
              labelText: l10n.universityAccountPasswordLabel,
              prefixIcon: const Icon(AppIcons.password_outlined),
              suffixIcon: IconButton(
                onPressed: account.isLoading
                    ? null
                    : () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                tooltip: _obscurePassword
                    ? l10n.mailShowPassword
                    : l10n.mailHidePassword,
                icon: Icon(
                  _obscurePassword
                      ? AppIcons.visibility_outlined
                      : AppIcons.visibility_off_outlined,
                ),
              ),
            ),
            onChanged: widget.onPasswordChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: widget.consent,
            enabled: !account.isLoading,
            title: Text(l10n.universityAccountStorageConsent),
            onChanged: (bool? value) => widget.onConsentChanged(value ?? false),
          ),
          if (account.hasError)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.universityAccountSecureStorageError,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.onboardingUniversityDraftHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the reader deliberately choose which protocol-specific services are
/// connected with the one local credential draft.
class OnboardingUniversityServicesStep extends ConsumerStatefulWidget {
  const OnboardingUniversityServicesStep({
    required this.identity,
    required this.onBusyChanged,
    super.key,
  });

  final UniversityIdentity? identity;
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<OnboardingUniversityServicesStep> createState() =>
      _OnboardingUniversityServicesStepState();
}

class _OnboardingUniversityServicesStepState
    extends ConsumerState<OnboardingUniversityServicesStep> {
  final Set<DirectService> _selected = <DirectService>{};
  final Set<DirectService> _connectedHere = <DirectService>{};
  final Map<DirectService, String> _errors = <DirectService, String>{};
  final TextEditingController _mailDisplayName = TextEditingController();
  bool _busy = false;
  DirectService? _activeService;
  String? _generalError;

  @override
  void dispose() {
    _mailDisplayName.dispose();
    super.dispose();
  }

  Future<void> _connectSelected() async {
    if (_busy || _selected.isEmpty) return;
    final UniversityAccountState? account = ref
        .read(universityAccountControllerProvider)
        .value;
    bool hasStoredIdentity = account?.hasIdentity ?? false;
    final UniversityIdentity? draft = widget.identity;
    final bool needsUniversityIdentity = _selected.any(
      (DirectService service) => service.usesUniversityIdentity,
    );
    if (needsUniversityIdentity &&
        !hasStoredIdentity &&
        (draft == null || !draft.isValid)) {
      setState(() {
        _generalError = context.l10n.universityAccountIdentityMissing;
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _generalError = null;
      _errors.clear();
    });
    widget.onBusyChanged(true);
    final UniversityServiceConnector connector = ref.read(
      universityServiceConnectorProvider,
    );
    try {
      for (final DirectService service in DirectService.values) {
        if (!_selected.contains(service) || _connectedHere.contains(service)) {
          continue;
        }
        if (mounted) setState(() => _activeService = service);
        final String? displayName = service == DirectService.mail
            ? (_mailDisplayName.text.trim().isEmpty
                  ? null
                  : _mailDisplayName.text.trim())
            : null;
        try {
          if (service == DirectService.nextcloud) {
            await ref
                .read(nextcloudAccountControllerProvider.notifier)
                .connect();
            final AsyncValue<NextcloudAccount?> nextcloud = ref.read(
              nextcloudAccountControllerProvider,
            );
            if (nextcloud.hasError) throw nextcloud.error!;
            if (nextcloud.value == null) continue;
          } else if (hasStoredIdentity) {
            await connector.connect(service, displayName: displayName);
          } else {
            await connector.connectAndRetain(
              service,
              draft!,
              displayName: displayName,
            );
            hasStoredIdentity = true;
            TextInput.finishAutofillContext();
          }
          if (!mounted) return;
          setState(() => _connectedHere.add(service));
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _errors[service] = universityAccountErrorMessage(
              context.l10n,
              service,
              error,
            );
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activeService = null;
        });
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final UniversityAccountState? account = ref
        .watch(universityAccountControllerProvider)
        .value;
    final Set<DirectService> alreadyConnected =
        ref.watch(connectedDirectServicesProvider).toSet()
          ..addAll(_connectedHere);
    final bool canUseIdentity =
        (account?.hasIdentity ?? false) || (widget.identity?.isValid ?? false);
    final bool canConnectSelection = _selected.any(
      (DirectService service) =>
          service == DirectService.nextcloud || canUseIdentity,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!canUseIdentity)
          Panel(child: Text(l10n.onboardingUniversityMissingDraft)),
        for (final DirectService service in DirectService.values) ...<Widget>[
          CheckboxListTile(
            value:
                alreadyConnected.contains(service) ||
                _selected.contains(service),
            enabled:
                !_busy &&
                !alreadyConnected.contains(service) &&
                (service == DirectService.nextcloud || canUseIdentity),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Icon(_serviceIcon(service)),
            title: Text(universityServiceLabel(l10n, service)),
            subtitle: _errors[service] != null
                ? Semantics(
                    liveRegion: true,
                    child: Text(
                      _errors[service]!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  )
                : Text(
                    alreadyConnected.contains(service)
                        ? l10n.universityAccountConnected
                        : service == DirectService.nextcloud
                        ? l10n.nextcloudSubtitle
                        : l10n.universityAccountDisconnected,
                  ),
            onChanged: (bool? selected) => setState(() {
              if (selected ?? false) {
                _selected.add(service);
              } else {
                _selected.remove(service);
              }
              _errors.remove(service);
            }),
          ),
          if (service == DirectService.mail &&
              _selected.contains(DirectService.mail) &&
              !alreadyConnected.contains(DirectService.mail))
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.md,
                bottom: AppSpacing.sm,
              ),
              child: TextField(
                controller: _mailDisplayName,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.name],
                decoration: InputDecoration(
                  labelText: l10n.mailSetupNameLabel,
                  helperText: l10n.mailSetupNameHint,
                  helperMaxLines: 2,
                  isDense: true,
                ),
              ),
            ),
          if (service == DirectService.hsaKi &&
              _selected.contains(DirectService.hsaKi) &&
              !alreadyConnected.contains(DirectService.hsaKi))
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.md,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                l10n.hsaKiOnboardingIntro,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
        ],
        if (_generalError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _generalError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        Semantics(
          liveRegion: _busy,
          label: _busy ? l10n.onboardingUniversityConnecting : null,
          child: FilledButton.icon(
            onPressed: _busy || _selected.isEmpty || !canConnectSelection
                ? null
                : _connectSelected,
            icon: _busy
                ? const ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: AppSizes.iconSmall,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(AppIcons.link),
            label: Text(
              _busy
                  ? l10n.onboardingUniversityConnecting
                  : l10n.onboardingUniversityConnectSelected,
            ),
          ),
        ),
        if (_busy && _activeService == DirectService.nextcloud) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => ref
                .read(nextcloudAccountControllerProvider.notifier)
                .cancelPendingLogin(),
            icon: const Icon(AppIcons.cancel_outlined),
            label: Text(l10n.nextcloudCancelLogin),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.onboardingUniversitySeparateSessions,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.colors.textSecondary),
        ),
      ],
    );
  }

  static IconData _serviceIcon(DirectService service) => switch (service) {
    DirectService.mail => AppIcons.mail_outline,
    DirectService.moodle => AppIcons.school_outlined,
    DirectService.grades => AppIcons.grade_outlined,
    DirectService.nextcloud => AppIcons.cloud_outlined,
    DirectService.hsaKi => AppIcons.message_2,
  };
}
