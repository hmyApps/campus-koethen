// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';
import '../../grades/domain/grade_failure.dart';
import '../../grades/presentation/grade_messages.dart';
import '../../hsa_ki/application/hsa_ki_consent.dart';
import '../../hsa_ki/domain/hsa_ki_failure.dart';
import '../../hsa_ki/presentation/hsa_ki_messages.dart';
import '../../mail/domain/mail_failure.dart';
import '../../mail/presentation/mail_error_messages.dart';
import '../../moodle/domain/moodle_failure.dart';
import '../../moodle/presentation/moodle_messages.dart';
import '../../nextcloud/domain/nextcloud_failure.dart';
import '../../nextcloud/presentation/nextcloud_messages.dart';
import '../../settings/domain/direct_service.dart';
import '../application/university_account_controller.dart';
import '../application/university_service_connector.dart';
import '../domain/university_identity.dart';

String universityServiceLabel(AppLocalizations l10n, DirectService service) =>
    switch (service) {
      DirectService.mail => l10n.universityAccountServiceMail,
      DirectService.moodle => l10n.universityAccountServiceMoodle,
      DirectService.grades => l10n.universityAccountServiceGrades,
      DirectService.nextcloud => l10n.nextcloudTitle,
      DirectService.hsaKi => l10n.hsaKiTitle,
    };

String universityAccountErrorMessage(
  AppLocalizations l10n,
  DirectService service,
  Object error,
) {
  if (error is UniversityAccountFailure) {
    return switch (error.kind) {
      UniversityAccountFailureKind.invalidIdentity =>
        l10n.universityAccountInvalidIdentity,
      UniversityAccountFailureKind.identityMissing =>
        l10n.universityAccountIdentityMissing,
      UniversityAccountFailureKind.secureStorageUnavailable =>
        l10n.universityAccountSecureStorageError,
      UniversityAccountFailureKind.operationBlocked =>
        l10n.universityAccountDeletionInProgress,
      UniversityAccountFailureKind.connectionRollbackIncomplete =>
        l10n.universityAccountConnectionRollbackError,
      UniversityAccountFailureKind.accountChangeCleanupIncomplete =>
        l10n.universityAccountChangeCleanupError,
      UniversityAccountFailureKind.accountChangeRollbackIncomplete =>
        l10n.universityAccountChangeRollbackError,
    };
  }
  if (error is MailFailure) return mailFailureMessage(l10n, error);
  if (error is MoodleFailure) return moodleFailureMessage(l10n, error);
  if (error is GradeFailure) return gradeFailureMessage(l10n, error);
  if (error is NextcloudFailure) return nextcloudFailureMessage(l10n, error);
  if (error is HsaKiFailure) return hsaKiFailureMessage(l10n, error);
  return l10n.universityAccountConnectFailed;
}

Future<UniversityServiceConnectionResult?> showUniversityAccountSetupSheet(
  BuildContext context, {
  DirectService initialService = DirectService.mail,
}) => showModalBottomSheet<UniversityServiceConnectionResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) =>
      UniversityAccountSetupSheet(initialService: initialService),
);

/// Collects the central identity and validates it against one deliberately
/// selected service before anything is retained.
class UniversityAccountSetupSheet extends ConsumerStatefulWidget {
  const UniversityAccountSetupSheet({required this.initialService, super.key});

  final DirectService initialService;

  @override
  ConsumerState<UniversityAccountSetupSheet> createState() =>
      _UniversityAccountSetupSheetState();
}

class _UniversityAccountSetupSheetState
    extends ConsumerState<UniversityAccountSetupSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _password = TextEditingController();
  late final List<DirectService> _validationServices;
  late DirectService _service;
  bool _consent = false;
  bool _showConsentError = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // HSA-GPT has its own consent screen (`AGENTS.md` §2). It is offered
    // here only while that screen's consent scope is open, i.e. when this
    // sheet was opened by the HSA-GPT connect flow — never as an ordinary
    // option of the generic setup or the account update.
    final bool hsaKiConsented = ref.read(hsaKiConsentGateProvider).isGranted;
    _validationServices = DirectService.universityIdentityServices
        .where(
          (DirectService service) =>
              service != DirectService.hsaKi || hsaKiConsented,
        )
        .toList(growable: false);
    _service = _validationServices.contains(widget.initialService)
        ? widget.initialService
        : _validationServices.first;
    final UniversityAccountState? current = ref
        .read(universityAccountControllerProvider)
        .value;
    _identifier.text = current?.identifier ?? '';
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final bool fieldsValid = _formKey.currentState?.validate() ?? false;
    setState(() => _showConsentError = !_consent);
    if (!fieldsValid || !_consent) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bool updating =
          ref.read(universityAccountControllerProvider).value?.hasIdentity ??
          false;
      final UniversityServiceConnector connector = ref.read(
        universityServiceConnectorProvider,
      );
      final UniversityIdentity identity = UniversityIdentity(
        identifier: _identifier.text,
        password: _password.text,
      );
      final UniversityServiceConnectionResult result;
      if (updating) {
        result = await connector.replaceIdentityAndReconnect(
          _service,
          identity,
        );
      } else {
        await connector.connectAndRetain(_service, identity);
        result = const UniversityServiceConnectionResult(identityChanged: true);
      }
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = universityAccountErrorMessage(context.l10n, _service, error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final UniversityAccountState? current = ref
        .watch(universityAccountControllerProvider)
        .value;
    final bool updating = current?.hasIdentity ?? false;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    updating
                        ? l10n.universityAccountUpdateTitle
                        : l10n.universityAccountSetupTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(l10n.universityAccountSetupIntro),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<DirectService>(
                    initialValue: _service,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.universityAccountValidationService,
                      prefixIcon: const Icon(AppIcons.shield_outlined),
                    ),
                    items: _validationServices
                        .map(
                          (DirectService service) =>
                              DropdownMenuItem<DirectService>(
                                value: service,
                                child: Text(
                                  universityServiceLabel(l10n, service),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (DirectService? value) {
                            if (value != null) setState(() => _service = value);
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _identifier,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    // The university's own login accepts either form for every
                    // direct service, so both autofill sources are offered.
                    autofillHints: const <String>[
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.universityAccountIdentifierLabel,
                      prefixIcon: const Icon(AppIcons.person_outline),
                    ),
                    validator: (String? value) => (value ?? '').trim().isEmpty
                        ? l10n.universityAccountIdentifierRequired
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.universityAccountPasswordLabel,
                      prefixIcon: const Icon(AppIcons.password_outlined),
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
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
                    validator: (String? value) => (value ?? '').isEmpty
                        ? l10n.universityAccountPasswordRequired
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _consent,
                    enabled: !_busy,
                    title: Text(l10n.universityAccountStorageConsent),
                    onChanged: (bool? value) => setState(() {
                      _consent = value ?? false;
                      _showConsentError = false;
                    }),
                  ),
                  if (_showConsentError)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.md),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.universityAccountStorageConsentRequired,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: colors.error),
                        ),
                      ),
                    ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: colors.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? Semantics(
                            liveRegion: true,
                            label: l10n.universityAccountSetupBusy,
                            excludeSemantics: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const SizedBox.square(
                                  dimension: AppSizes.icon,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(l10n.universityAccountSetupBusy),
                                ),
                              ],
                            ),
                          )
                        : Text(l10n.universityAccountSetupSubmit),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
