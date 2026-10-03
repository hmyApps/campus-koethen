// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/links/safe_link_launcher.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../settings/domain/direct_service.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../../university_account/domain/university_identity.dart';
import '../../university_account/presentation/university_account_setup_sheet.dart'
    show universityAccountErrorMessage;
import '../application/mail_providers.dart';
import '../domain/hsa_mail_profile.dart';
import '../domain/mail_credentials.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../app/app_modules.dart';

/// Sign-in screen for the student mailbox.
///
/// Collects exactly two inputs — the email address (which is also the IMAP and
/// SMTP username and the sender) and the password. It explains, before anything
/// is typed, that the connection is direct and encrypted, that campus servers
/// never receive the credentials or any mail, and that the credentials are kept
/// only in the device's secure keystore.
class MailSetupScreen extends ConsumerStatefulWidget {
  const MailSetupScreen({super.key});

  @override
  ConsumerState<MailSetupScreen> createState() => _MailSetupScreenState();
}

class _MailSetupScreenState extends ConsumerState<MailSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _busy = false;
  bool _reuseForOtherServices = false;

  @override
  void initState() {
    super.initState();
    final String? identifier = ref
        .read(universityAccountControllerProvider)
        .value
        ?.identifier;
    if (identifier != null) {
      final String trimmed = identifier.trim();
      _emailController.text = trimmed.contains('@')
          ? trimmed
          : '$trimmed@hs-anhalt.de';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Puts the caret in the first field that failed validation.
  ///
  /// Without this the form only reddened a label that may well be off screen,
  /// so pressing "sign in" looked like it did nothing at all.
  void _focusFirstInvalidField() {
    final bool emailInvalid = !isValidEmailAddress(
      normalizeEmailAddress(_emailController.text),
    );
    if (emailInvalid) {
      _emailFocus.requestFocus();
      return;
    }
    if (_passwordController.text.isEmpty) _passwordFocus.requestFocus();
  }

  Future<void> _submit() async {
    final AppLocalizations l10n = context.l10n;
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
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
            DirectService.mail,
            UniversityIdentity(
              identifier: _emailController.text,
              password: _passwordController.text,
            ),
            displayName: _nameController.text,
            retainIdentity: _reuseForOtherServices,
          );
      // Lets the password manager offer to store what was just entered. Only
      // after a successful sign-in: offering to save a password that turned
      // out to be wrong is worse than not offering at all.
      TextInput.finishAutofillContext();
      // On success the gate rebuilds into the inbox; nothing else to do here.
    } catch (error) {
      // If the user already left this screen (back/cancel), a late failure
      // must not surface on whatever screen they navigated to next.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            universityAccountErrorMessage(l10n, DirectService.mail, error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWebmail() async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final HsaMailProfile profile = ref.read(hsaMailProfileProvider);
    final LinkLaunchResult result = await ref
        .read(linkLauncherProvider)
        .open(profile.webmailUrl);
    if (result != LinkLaunchResult.opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLinkNotOpened)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final AppSettings settings = ref.watch(settingsProvider);
    final bool hasCentralIdentity =
        ref.watch(universityAccountControllerProvider).value?.hasIdentity ??
        false;

    return PopScope(
      canPop: !_busy,
      child: ScreenScaffold(
        eyebrow: ModuleCategory.study.label(l10n),
        title: l10n.mailTitle,
        backEnabled: !_busy,
        body: SafeArea(
          child: Form(
            key: _formKey,
            // Without this a password manager has nothing to fill and nothing to
            // save, so the university password gets typed by hand — or pasted
            // through the clipboard, which is worse.
            child: AutofillGroup(
              child: ListView(
                padding: EdgeInsets.all(context.metrics.screenPadding),
                children: <Widget>[
                  Text(l10n.mailSetupHeadline, style: text.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  _InfoCard(
                    icon: AppIcons.lock_outline,
                    child: Text(l10n.mailSetupIntro),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: AppIcons.shield_outlined,
                    child: Text(l10n.mailSetupPrivacy),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: AppIcons.info_outline,
                    child: Text(l10n.aboutIndependenceNotice),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.name],
                    decoration: InputDecoration(
                      labelText: l10n.mailSetupNameLabel,
                      helperText: l10n.mailSetupNameHint,
                      helperMaxLines: 2,
                      prefixIcon: const Icon(AppIcons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.mailSetupEmailLabel,
                      hintText: l10n.mailSetupEmailHint,
                      prefixIcon: const Icon(AppIcons.alternate_email),
                    ),
                    validator: (String? value) =>
                        isValidEmailAddress(normalizeEmailAddress(value ?? ''))
                        ? null
                        : l10n.mailSetupInvalidEmail,
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
                      labelText: l10n.mailSetupPasswordLabel,
                      prefixIcon: const Icon(AppIcons.password_outlined),
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        // The one icon button on this screen that used to have no
                        // name at all, on the field where getting it wrong costs
                        // the most. The label states what the tap will do.
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
                    validator: (String? value) =>
                        (value == null || value.isEmpty)
                        ? l10n.mailSetupPasswordRequired
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
                  const SizedBox(height: AppSpacing.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(AppIcons.download_outlined),
                    title: Text(l10n.settingsMailDownloadAttachments),
                    subtitle: Text(
                      l10n.settingsMailDownloadAttachmentsSubtitle,
                    ),
                    value: settings.mailDownloadAttachments,
                    onChanged: _busy
                        ? null
                        : (bool value) => ref
                              .read(settingsProvider.notifier)
                              .setMailDownloadAttachments(value),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? Semantics(
                            liveRegion: true,
                            label: l10n.mailSetupChecking,
                            excludeSemantics: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const SizedBox(
                                  height: AppSizes.icon,
                                  width: AppSizes.icon,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(l10n.mailSetupChecking),
                              ],
                            ),
                          )
                        : Text(l10n.mailSetupSubmit),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: _busy ? null : _openWebmail,
                    icon: const Icon(AppIcons.open_in_new),
                    label: Text(l10n.mailSetupWebmailLink),
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
  const _InfoCard({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

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
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
