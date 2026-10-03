// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../../settings/domain/direct_service.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../../university_account/domain/university_identity.dart';
import '../../university_account/presentation/university_account_setup_sheet.dart'
    show universityAccountErrorMessage;
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// Connect screen for Moodle.
///
/// States, before anything is typed, that the connection is direct to
/// moodle.hs-anhalt.de, that no Moodle data reaches this app's servers, and that
/// only a session token — not the password — is stored in the device's secure
/// keystore.
class MoodleSetupScreen extends ConsumerStatefulWidget {
  const MoodleSetupScreen({super.key});

  @override
  ConsumerState<MoodleSetupScreen> createState() => _MoodleSetupScreenState();
}

class _MoodleSetupScreenState extends ConsumerState<MoodleSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  bool _reuseForOtherServices = false;

  @override
  void initState() {
    super.initState();
    // The identifier is never a secret — pre-filling it saves re-typing it
    // even when the stored password itself turned out to be wrong.
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
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final AppLocalizations l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(universityServiceConnectorProvider)
          .connectWithIdentity(
            DirectService.moodle,
            UniversityIdentity(
              identifier: _usernameController.text.trim(),
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
            universityAccountErrorMessage(l10n, DirectService.moodle, error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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
        title: l10n.moodleTitle,
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
                  Text(l10n.moodleSetupHeadline, style: text.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  _InfoCard(
                    icon: AppIcons.lock_outline,
                    iconColor: context.colors.primary,
                    text: l10n.moodleSetupIntro,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: AppIcons.shield_outlined,
                    iconColor: context.colors.primary,
                    text: l10n.moodlePrivacyNote,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: AppIcons.info_outline,
                    text: l10n.aboutIndependenceNotice,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _usernameController,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: l10n.moodleUsernameLabel,
                      prefixIcon: const Icon(AppIcons.person_outline),
                    ),
                    validator: (String? value) =>
                        (value == null || value.trim().isEmpty)
                        ? l10n.moodleUsernameRequired
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.moodlePasswordLabel,
                      prefixIcon: const Icon(AppIcons.password_outlined),
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        // Without a name this is the one control on the screen a
                        // screen reader cannot describe — on the password field.
                        tooltip: _obscurePassword
                            ? l10n.moodleShowPassword
                            : l10n.moodleHidePassword,
                        icon: Icon(
                          _obscurePassword
                              ? AppIcons.visibility_outlined
                              : AppIcons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (String? value) =>
                        (value == null || value.isEmpty)
                        ? l10n.moodlePasswordRequired
                        : null,
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
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? Semantics(
                            liveRegion: true,
                            label: l10n.moodleConnecting,
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
                                Flexible(child: Text(l10n.moodleConnecting)),
                              ],
                            ),
                          )
                        : Text(l10n.moodleConnectButton),
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
  const _InfoCard({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: AppSizes.icon, color: iconColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
