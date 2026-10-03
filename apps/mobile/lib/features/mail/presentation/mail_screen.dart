// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/mail_account_controller.dart';
import 'mail_error_messages.dart';
import 'mail_inbox_screen.dart';
import 'mail_setup_screen.dart';

/// Entry point of the student email client at `/more/mail`.
///
/// A pure gate: it shows the sign-in screen while there is no stored account
/// and the inbox once one exists. Signing in and removing the account both flow
/// through [mailAccountControllerProvider], so the switch is automatic.
class MailScreen extends ConsumerWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<MailAccountState> account = ref.watch(
      mailAccountControllerProvider,
    );
    return account.when(
      loading: () => const Scaffold(body: LoadingView()),
      // "Could not read the account" is not the same thing as "there is no
      // account". Showing the sign-in form for a keystore that failed to open
      // reads as data loss and sends people through a needless re-login with
      // their university password.
      error: (Object error, _) => Scaffold(
        body: EmptyView(
          icon: AppIcons.error_outline,
          title: l10n.mailAccountLoadFailedTitle,
          message:
              '${l10n.mailAccountLoadFailedBody} '
              '${mailFailureMessage(l10n, error)}',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(mailAccountControllerProvider),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.mailRetry),
          ),
        ),
      ),
      data: (MailAccountState state) =>
          state.isSignedIn ? const MailInboxScreen() : const MailSetupScreen(),
    );
  }
}
