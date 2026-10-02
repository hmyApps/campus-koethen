// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/sign_out_everywhere_controller.dart';
import '../domain/direct_service.dart';
import '../../university_account/application/university_account_controller.dart';

extension on DirectService {
  /// Reuses each feature's own screen title so the name never drifts out of
  /// sync with what the user sees when actually signing in.
  String label(AppLocalizations l10n) => switch (this) {
    DirectService.mail => l10n.settingsSectionMail,
    DirectService.moodle => l10n.moodleTitle,
    DirectService.grades => l10n.gradesTitle,
  };
}

/// Completely removes the central identity after every connected direct
/// service has completed its own canonical logout/wipe.
class SignOutEverywhereTile extends ConsumerStatefulWidget {
  const SignOutEverywhereTile({super.key});

  @override
  ConsumerState<SignOutEverywhereTile> createState() =>
      _SignOutEverywhereTileState();
}

class _SignOutEverywhereTileState extends ConsumerState<SignOutEverywhereTile> {
  /// True while the sign-outs are running.
  ///
  /// Signing out of three services means three network round trips, and the
  /// tile used to look completely idle throughout — so a second tap was easy
  /// and the wait was unexplained.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<DirectService> connected = ref.watch(
      connectedDirectServicesProvider,
    );
    final bool hasIdentity = ref.watch(
      universityAccountControllerProvider.select(
        (AsyncValue<UniversityAccountState> value) =>
            value.value?.hasIdentity ?? false,
      ),
    );
    final bool canDelete = connected.isNotEmpty || hasIdentity;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: _busy
          ? const SizedBox(
              width: AppSizes.icon,
              height: AppSizes.icon,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Icon(
              AppIcons.delete_outline,
              color: canDelete ? colors.error : null,
            ),
      title: Text(
        l10n.settingsSignOutEverywhere,
        style: canDelete && !_busy ? TextStyle(color: colors.error) : null,
      ),
      subtitle: Text(
        hasIdentity
            ? l10n.universityAccountDeleteSubtitle
            : l10n.settingsSignOutEverywhereSubtitle(connected.length),
      ),
      enabled: canDelete && !_busy,
      onTap: canDelete && !_busy
          ? () => _confirmAndSignOut(context, ref, connected)
          : null,
    );
  }

  Future<void> _confirmAndSignOut(
    BuildContext context,
    WidgetRef ref,
    List<DirectService> connected,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final String serviceNames = connected
        .map((DirectService s) => s.label(l10n))
        .join(', ');

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            icon: Icon(
              AppIcons.delete_outline,
              color: Theme.of(dialogContext).colorScheme.error,
            ),
            title: Text(l10n.settingsSignOutEverywhereConfirmTitle),
            content: Text(
              connected.isEmpty
                  ? l10n.universityAccountDeleteConfirmNoServices
                  : l10n.settingsSignOutEverywhereConfirmMessage(serviceNames),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.universityAccountDeleteConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    await _runSignOut(context, ref);
  }

  /// Runs the actual sign-out and reports the outcome. On a partial failure it
  /// offers a retry that targets only the services still connected — already
  /// signed-out ones are never asked to confirm again.
  Future<void> _runSignOut(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    setState(() => _busy = true);
    final SignOutEverywhereResult result;
    try {
      result = await ref.read(signOutEverywhereServiceProvider).signOutAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!context.mounted) return;

    if (result.isFullSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsSignOutEverywhereSuccess)),
      );
      return;
    }

    if (result.failedServices.isEmpty && !result.identityDeleted) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          icon: Icon(
            AppIcons.error_outline,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: Text(l10n.universityAccountDeleteIncompleteTitle),
          content: Text(l10n.universityAccountDeleteIncompleteMessage),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).okButtonLabel,
              ),
            ),
          ],
        ),
      );
      return;
    }

    final String failedNames = result.failedServices
        .map((DirectService s) => s.label(l10n))
        .join(', ');
    final bool retry =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            icon: Icon(
              AppIcons.error_outline,
              color: Theme.of(dialogContext).colorScheme.error,
            ),
            title: Text(l10n.settingsSignOutEverywherePartialTitle),
            content: Text(
              l10n.settingsSignOutEverywherePartialMessage(failedNames),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  MaterialLocalizations.of(dialogContext).okButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.settingsSignOutEverywhereRetry),
              ),
            ],
          ),
        ) ??
        false;
    if (!retry || !context.mounted) return;

    await _runSignOut(context, ref);
  }
}
