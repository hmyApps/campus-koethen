// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../../notifications/presentation/pre_permission_sheet.dart';
import '../application/moodle_account_controller.dart';
import '../domain/moodle_account.dart';
import 'moodle_messages.dart';
import 'moodle_overview_screen.dart';
import 'moodle_setup_screen.dart';

/// Entry point of the Moodle area at `/more/moodle`.
///
/// A pure gate: the setup screen while no account is connected, the overview
/// once a token exists. Connecting and disconnecting both flow through
/// [moodleAccountControllerProvider], so the switch is automatic.
class MoodleScreen extends ConsumerWidget {
  const MoodleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Contextual entry point D of the UX spec (§ 2.2): connecting Moodle is
    // the moment submission deadlines start existing on this device, and they
    // only ever surface in the 08:00 overview — P5 rules out a reminder of
    // their own.
    //
    // Offered from the gate rather than from the setup screen, because the
    // setup screen is exactly what stops existing the moment the connection
    // succeeds: a sheet asked for there would be asked for by a widget on its
    // way out. The gate stays. The offer is a follow-up, never a gate of its
    // own — the connection stands either way, and
    // [maybeOfferNotificationOptIn] stays silent for anyone who has already
    // answered.
    ref.listen<AsyncValue<MoodleAccount?>>(moodleAccountControllerProvider, (
      AsyncValue<MoodleAccount?>? previous,
      AsyncValue<MoodleAccount?> next,
    ) {
      // Only on a real connection event: a previous state that was still
      // loading (rather than a confirmed "no account") used to satisfy this
      // guard too, so every loading→data transition — a plain reopen of the
      // tab — could re-offer the opt-in.
      if (previous?.hasValue != true) return;
      if (previous?.value != null || next.value == null) return;
      unawaited(maybeOfferNotificationOptIn(context, ref));
    });

    final AsyncValue<MoodleAccount?> account = ref.watch(
      moodleAccountControllerProvider,
    );
    final AppLocalizations l10n = context.l10n;
    return account.when(
      loading: () => const Scaffold(body: LoadingView()),
      // "Could not read the token" is not "not connected". Falling back to the
      // setup form makes a stored connection look gone and invites a pointless
      // re-entry of the university password.
      error: (Object error, _) => Scaffold(
        body: EmptyView(
          icon: AppIcons.error_outline,
          title: l10n.moodleAccountLoadFailedTitle,
          message:
              '${l10n.moodleAccountLoadFailedBody} '
              '${moodleFailureMessage(l10n, error)}',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(moodleAccountControllerProvider),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.moodleRefresh),
          ),
        ),
      ),
      data: (MoodleAccount? state) => state == null
          ? const MoodleSetupScreen()
          : const MoodleOverviewScreen(),
    );
  }
}
