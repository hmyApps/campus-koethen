// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/links/safe_link_launcher.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../settings/domain/direct_service.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../../university_account/domain/university_identity.dart';
import '../../university_account/presentation/university_account_setup_sheet.dart'
    show universityAccountErrorMessage;
import '../application/grades_providers.dart';
import '../domain/grade_credentials.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// Sign-in screen for the HIS-QIS exam portal.
///
/// Explains, before anything is typed, that the connection is direct and
/// encrypted to the official portal, that the campus servers never receive the
/// credentials or grades, and that the credentials are kept only in the device's
/// secure keystore — and requires explicit consent to that local storage.
class GradeSetupScreen extends ConsumerStatefulWidget {
  const GradeSetupScreen({super.key});

  @override
  ConsumerState<GradeSetupScreen> createState() => _GradeSetupScreenState();
}

class _GradeSetupScreenState extends ConsumerState<GradeSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _consent = false;
  bool _consentMissing = false;
  bool _busy = false;
  bool _reuseForOtherServices = false;

  @override
  void initState() {
    super.initState();
    final String? identifier = ref
        .read(universityAccountControllerProvider)
        .value
        ?.identifier;
    if (identifier != null) _usernameController.text = identifier;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Puts the caret in the first field that failed validation.
  void _focusFirstInvalidField() {
    if (!isValidUsername(_usernameController.text)) {
      _usernameFocus.requestFocus();
      return;
    }
    if (!isValidPassword(_passwordController.text)) {
      _passwordFocus.requestFocus();
    }
  }

  Future<void> _submit() async {
    final AppLocalizations l10n = context.l10n;
    if (_busy) return;
    final bool valid = _formKey.currentState?.validate() ?? false;
    // A snack bar was the wrong shape for this: it disappears, it is nowhere
    // near the checkbox, and it leaves the control itself looking fine. The
    // error now stays under the checkbox until it is answered.
    setState(() => _consentMissing = !_consent);
    if (!_consent) return;
    if (!valid) {
      _focusFirstInvalidField();
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(universityServiceConnectorProvider)
          .connectWithIdentity(
            DirectService.grades,
            UniversityIdentity(
              identifier: _usernameController.text,
              password: _passwordController.text,
            ),
            retainIdentity: _reuseForOtherServices,
          );
      // Only after success: offering to save a rejected password is worse
      // than not offering at all.
      TextInput.finishAutofillContext();
      // On success the gate rebuilds into the overview.
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            universityAccountErrorMessage(l10n, DirectService.grades, error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPortal() async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Before setup the account's portal is not known yet; the legacy portal's
    // public entry page is the long-standing "open in browser" target.
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(ref.read(legacyQisProfileProvider).portalUrl);
    if (result != LinkLaunchResult.opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLinkNotOpened)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasCentralIdentity =
        ref.watch(universityAccountControllerProvider).value?.hasIdentity ??
        false;

    return PopScope(
      canPop: !_busy,
      child: ScreenScaffold(
        eyebrow: ModuleCategory.study.label(l10n),
        title: l10n.gradesTitle,
        backEnabled: !_busy,
        body: SafeArea(
          child: Form(
            key: _formKey,
            // Without this a password manager has nothing to fill and nothing to
            // save, so the university password gets typed by hand.
            child: AutofillGroup(
              child: ListView(
                padding: EdgeInsets.all(context.metrics.screenPadding),
                children: <Widget>[
                  Text(l10n.gradeSetupHeadline, style: text.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  _InfoCard(
                    icon: AppIcons.lock_outline,
                    text: l10n.gradeSetupIntro,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: AppIcons.shield_outlined,
                    text: l10n.gradeSetupPrivacy,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: AppIcons.info_outline,
                    text: l10n.aboutIndependenceNotice,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: l10n.gradeSetupUsernameLabel,
                      prefixIcon: const Icon(AppIcons.person_outline),
                    ),
                    validator: (String? value) => isValidUsername(value)
                        ? null
                        : l10n.gradeSetupUsernameRequired,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.gradeSetupPasswordLabel,
                      prefixIcon: const Icon(AppIcons.password_outlined),
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        // The state has to be spoken, not only drawn: the glyph
                        // alone tells a screen reader nothing about whether the
                        // password is currently on screen.
                        tooltip: _obscurePassword
                            ? l10n.gradesShowPassword
                            : l10n.gradesHidePassword,
                        icon: Icon(
                          _obscurePassword
                              ? AppIcons.visibility_outlined
                              : AppIcons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (String? value) => isValidPassword(value)
                        ? null
                        : l10n.gradeSetupPasswordRequired,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CheckboxListTile(
                    value: _consent,
                    onChanged: _busy
                        ? null
                        : (bool? v) => setState(() {
                            _consent = v ?? false;
                            if (_consent) _consentMissing = false;
                          }),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    isError: _consentMissing,
                    title: Text(l10n.gradeSetupConsent, style: text.bodyMedium),
                  ),
                  if (_consentMissing)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.gradeSetupConsentRequired,
                          style: text.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (!hasCentralIdentity) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      value: _reuseForOtherServices,
                      enabled: !_busy,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.universityAccountReuseConsent),
                      onChanged: (bool? value) => setState(
                        () => _reuseForOtherServices = value ?? false,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? Semantics(
                            liveRegion: true,
                            label: l10n.gradesSyncingSemantic,
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
                                Flexible(child: Text(l10n.gradesSyncing)),
                              ],
                            ),
                          )
                        : Text(l10n.gradeSetupSubmit),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: _busy ? null : _openPortal,
                    icon: const Icon(AppIcons.open_in_new),
                    label: Text(l10n.gradesOpenPortalLink),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // The automatic portal choice was invisible here, so the old
                  // fixed "QIS portal" link quietly sent HISinOne students to the
                  // wrong place. Saying it out loud is half the fix; the link
                  // steering below is the other half.
                  Text(
                    l10n.gradesPortalAutodetectHint,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: AppSizes.icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
