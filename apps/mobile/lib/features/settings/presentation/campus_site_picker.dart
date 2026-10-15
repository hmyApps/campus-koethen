// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/settings_controller.dart';
import '../../../core/site/campus_site.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';

/// The three campus sites as a single choice.
///
/// Shared by the first-run setup and the settings: both store the same
/// preference, so both show the same control. Nothing is preselected — an
/// unanswered question stays unanswered, and the app then behaves as for
/// Köthen.
class CampusSiteOptions extends ConsumerWidget {
  const CampusSiteOptions({this.onChosen, super.key});

  /// Called after the choice is stored, e.g. to close a sheet.
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final CampusSite? chosen = ref.watch(
      settingsProvider.select((AppSettings s) => s.campusSite),
    );
    return RadioGroup<CampusSite>(
      groupValue: chosen,
      onChanged: (CampusSite? site) async {
        if (site == null) return;
        await ref.read(settingsProvider.notifier).setCampusSite(site);
        onChosen?.call();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final CampusSite site in CampusSite.values)
            RadioListTile<CampusSite>.adaptive(
              value: site,
              title: Text(site.label(l10n)),
            ),
        ],
      ),
    );
  }
}

/// Opens the site choice as a bottom sheet (settings).
Future<void> showCampusSitePickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      final AppLocalizations l10n = context.l10n;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.settingsCampusSite,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  l10n.settingsCampusSiteHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              CampusSiteOptions(
                onChosen: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
