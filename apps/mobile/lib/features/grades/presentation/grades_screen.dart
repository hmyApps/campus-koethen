// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/grade_account_controller.dart';
import 'grade_messages.dart';
import 'grade_setup_screen.dart';
import 'grades_overview_screen.dart';

/// Entry point of the grades area at `/more/grades`.
///
/// A pure gate: the setup screen while no account is stored, the overview once
/// one exists. Signing in and deleting the account both flow through
/// [gradeAccountControllerProvider], so the switch is automatic.
class GradesScreen extends ConsumerWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<GradeAccountState> account = ref.watch(
      gradeAccountControllerProvider,
    );
    return account.when(
      loading: () => const Scaffold(body: LoadingView()),
      // A keystore that failed to open — after an OS update, say — is not the
      // same as "no account". Falling back to the sign-in form makes a stored
      // account look deleted and sends people to re-enter a password that was
      // never the problem.
      error: (Object error, _) => Scaffold(
        body: EmptyView(
          icon: AppIcons.error_outline,
          title: l10n.gradesAccountLoadFailedTitle,
          message:
              '${l10n.gradesAccountLoadFailedBody} '
              '${gradeFailureMessage(l10n, error)}',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(gradeAccountControllerProvider),
            icon: const Icon(AppIcons.refresh),
            label: Text(l10n.gradesRetry),
          ),
        ),
      ),
      data: (GradeAccountState state) => state.isSignedIn
          ? const GradesOverviewScreen()
          : const GradeSetupScreen(),
    );
  }
}
