// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/documents/app_document.dart';
import '../../../core/locale/locale_mode.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../app/app_modules.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/l10n.dart';
import 'personalisation_tiles.dart';
import '../../university_account/presentation/university_account_card.dart';
import '../../canteen/application/canteen_providers.dart';
import '../../requests/application/requests_local_data_wiper.dart';
import '../../canteen/data/canteen_models.dart';
import '../../canteen/presentation/canteen_picker_sheet.dart';
import '../../news/application/channel_subscriptions.dart';
import '../../mail/application/mail_providers.dart';
import '../../mail/domain/mail_cache_store.dart';
import '../../timetable/application/timetable_providers.dart';
import '../../timetable/data/timetable_models.dart';
import '../../timetable/presentation/timetable_group_picker_sheet.dart';

/// Local settings. Everything here stays on the device — the app works
/// entirely without a user account.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppSettings settings = ref.watch(settingsProvider);
    final int selectedChannels = ref
        .watch(channelSubscriptionProvider)
        .selectedSlugs
        .length;
    final List<Canteen> canteens =
        ref.watch(canteensProvider).value?.value ?? const <Canteen>[];
    final String? canteenSlug = ref.watch(selectedCanteenSlugProvider);
    final String canteenName =
        canteens
            .where((Canteen canteen) => canteen.slug == canteenSlug)
            .map((Canteen canteen) => canteen.displayName)
            .firstOrNull ??
        l10n.settingsPreferredCanteenNone;
    final List<TimetableGroup> timetableGroups =
        ref.watch(timetableGroupsProvider).value?.value ??
        const <TimetableGroup>[];
    final String? timetableGroupId = ref.watch(
      selectedTimetableGroupIdProvider,
    );
    final String timetableGroupName =
        timetableGroups
            .where((TimetableGroup group) => group.id == timetableGroupId)
            .map((TimetableGroup group) => group.shortName)
            .firstOrNull ??
        l10n.settingsTimetableGroupNone;

    return ScreenScaffold(
      eyebrow: ModuleCategory.app.label(l10n),
      title: l10n.settingsTitle,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: <Widget>[
          // Every section opens with its own bar line, which is what separates
          // them now — a rule between two settings and a rule between two
          // sections used to be the same hairline.
          SectionHeader(label: l10n.settingsSectionAppearance),
          _LanguageTile(settings: settings),
          const BrightnessPreferenceTile(),
          const AccentSchemeTile(),
          const ReducedMotionTile(),
          SectionHeader(label: l10n.settingsSectionPersonalisation),
          ListTile(
            leading: const Icon(AppIcons.space_dashboard_outlined),
            title: Text(l10n.settingsNavigation),
            subtitle: Text(l10n.settingsNavigationSubtitle),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => context.push(AppRoutes.settingsNavigation),
          ),
          ListTile(
            leading: const Icon(AppIcons.notifications_outlined),
            title: Text(l10n.settingsNotifications),
            subtitle: Text(l10n.settingsNotificationsSubtitle),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => context.push(AppRoutes.settingsNotifications),
          ),
          SectionHeader(label: l10n.settingsSectionContent),
          ListTile(
            leading: const Icon(AppIcons.rss_feed_outlined),
            title: Text(l10n.settingsChannels),
            subtitle: Text(l10n.newsChannelCountLabel(selectedChannels)),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => context.push(AppRoutes.channels),
          ),
          ListTile(
            leading: const Icon(AppIcons.restaurant_outlined),
            title: Text(l10n.settingsPreferredCanteen),
            subtitle: Text(canteenName),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => showCanteenPickerSheet(context),
          ),
          ListTile(
            leading: const Icon(AppIcons.school_outlined),
            title: Text(l10n.settingsTimetableGroup),
            subtitle: Text(timetableGroupName),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => showTimetableGroupPickerSheet(context, ref),
          ),
          SectionHeader(label: l10n.settingsSectionMail),
          SwitchListTile(
            secondary: const Icon(AppIcons.download_outlined),
            title: Text(l10n.settingsMailDownloadAttachments),
            subtitle: Text(l10n.settingsMailDownloadAttachmentsSubtitle),
            value: settings.mailDownloadAttachments,
            onChanged: (bool value) => ref
                .read(settingsProvider.notifier)
                .setMailDownloadAttachments(value),
          ),
          const _MailCacheTile(),
          SectionHeader(label: l10n.settingsSectionAccounts),
          const UniversityAccountCard(),
          SectionHeader(label: l10n.settingsSectionData),
          ListTile(
            leading: const Icon(AppIcons.restart_alt_outlined),
            title: Text(l10n.onboardingRestart),
            subtitle: Text(l10n.onboardingRestartSubtitle),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () async {
              await ref
                  .read(settingsProvider.notifier)
                  .setOnboardingCompleted(false);
              if (!context.mounted) return;
              context.go(AppRoutes.onboarding);
            },
          ),
          const _RequestsWipeTile(),
          const _ResetTile(),
          SectionHeader(label: l10n.settingsSectionLegal),
          ListTile(
            leading: const Icon(AppIcons.info_outline),
            title: Text(l10n.settingsAbout),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => context.push(AppRoutes.about),
          ),
          ListTile(
            leading: const Icon(AppIcons.gavel_outlined),
            title: Text(l10n.settingsImprint),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => context.push(AppRoutes.imprint),
          ),
          ListTile(
            leading: const Icon(AppIcons.privacy_tip_outlined),
            title: Text(l10n.settingsPrivacy),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => context.push(AppRoutes.privacy),
          ),
        ],
      ),
    );
  }
}

class _MailCacheTile extends ConsumerStatefulWidget {
  const _MailCacheTile();

  @override
  ConsumerState<_MailCacheTile> createState() => _MailCacheTileState();
}

class _MailCacheTileState extends ConsumerState<_MailCacheTile> {
  late Future<MailCacheStats> _stats;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _stats = ref.read(mailCacheStoreProvider).stats();
  }

  Future<void> _clear() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    await ref.read(mailCacheStoreProvider).clearCachedBodies();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _reload();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.settingsMailCacheCleared)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return FutureBuilder<MailCacheStats>(
      future: _stats,
      builder: (BuildContext context, AsyncSnapshot<MailCacheStats> snapshot) {
        final MailCacheStats? stats = snapshot.data;
        final String size = humanFileSize(
          stats?.byteCount ?? 0,
          locale: Localizations.localeOf(context).languageCode,
        );
        return ListTile(
          leading: const Icon(AppIcons.download_outlined),
          title: Text(l10n.settingsMailCache),
          subtitle: Text(
            stats == null
                ? l10n.commonLoading
                : l10n.settingsMailCacheSubtitle(stats.bodyCount, size),
          ),
          trailing: TextButton(
            onPressed: _clearing || (stats?.bodyCount ?? 0) == 0
                ? null
                : _clear,
            child: Text(l10n.settingsMailCacheClear),
          ),
        );
      },
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    String label(LocaleMode mode) => switch (mode) {
      LocaleMode.german => l10n.settingsLanguageGerman,
      LocaleMode.english => l10n.settingsLanguageEnglish,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.metrics.screenPadding,
          ),
          child: Text(
            l10n.settingsLanguage,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        RadioGroup<LocaleMode>(
          groupValue: settings.localeMode,
          onChanged: (LocaleMode? value) {
            if (value == null) return;
            // Changing the locale rebuilds MaterialApp and every inherited
            // localisation dependency below it. Doing that synchronously
            // inside RadioGroup's own notification can leave the group
            // iterating dependents that have already moved during the root
            // rebuild. Finish the interaction frame before changing the root.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              ref.read(settingsProvider.notifier).setLocaleMode(value);
            });
          },
          child: Column(
            children: <Widget>[
              for (final LocaleMode mode in LocaleMode.values)
                RadioListTile<LocaleMode>.adaptive(
                  value: mode,
                  title: Text(label(mode)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Resets appearance and preferences after an explicit confirmation.
///
/// Deliberately scoped and says so: the secure stores behind mail, grades and
/// Moodle are untouched, because half-deleting an account from a settings
/// screen would leave credentials without their data — those have their own
/// "remove account" action.
class _ResetTile extends ConsumerWidget {
  const _ResetTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return ListTile(
      leading: Icon(
        AppIcons.restore,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(l10n.settingsReset),
      subtitle: Text(l10n.settingsResetSubtitle),
      onTap: () async {
        final bool confirmed =
            await showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) => AlertDialog(
                icon: const Icon(AppIcons.restore),
                title: Text(l10n.settingsResetConfirmTitle),
                // Says what survives as well as what goes. The old dialog
                // listed neither, and the reset silently re-armed onboarding.
                content: Text(
                  '${l10n.settingsResetConfirmMessage}\n\n'
                  '${l10n.settingsResetKeepsOnboarding}',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(
                      MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(l10n.settingsResetConfirmAction),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed || !context.mounted) return;
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        final bool complete = await ref
            .read(settingsProvider.notifier)
            .resetLocalPreferences();
        // A half reset that reports "done" is how old values reappear after
        // the next start with nothing having warned about it.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              complete ? l10n.settingsResetDone : l10n.settingsResetIncomplete,
            ),
          ),
        );
      },
    );
  }
}

/// Deletes everything the requests feature keeps on this device.
///
/// The requests integration fell through both existing rasters: it is not
/// user-authenticated, so "sign out everywhere" logically does not cover it,
/// and it is not a preference, so the reset does not either. Yet it holds the
/// most sensitive data in the app — a copy of the student ID and the status
/// links, which are bearer tokens for the submitted cases. Anyone wanting
/// "everything personal off this device" had no path to it at all (S-04 /
/// SET-2).
///
/// Deliberately named "delete local data" rather than "sign out": there is no
/// session here to end.
class _RequestsWipeTile extends ConsumerWidget {
  const _RequestsWipeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return ListTile(
      leading: Icon(
        AppIcons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(l10n.settingsRequestsWipe),
      subtitle: Text(l10n.settingsRequestsWipeSubtitle),
      onTap: () async {
        final bool confirmed =
            await showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) => AlertDialog(
                icon: const Icon(AppIcons.delete_outline),
                title: Text(l10n.settingsRequestsWipeConfirmTitle),
                content: Text(l10n.settingsRequestsWipeConfirmMessage),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(
                      MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(l10n.settingsRequestsWipeConfirmAction),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed || !context.mounted) return;

        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        final bool complete = await ref
            .read(requestsLocalDataWiperProvider)
            .wipe();
        // Reported honestly: leaving the student ID behind while saying it is
        // gone is the failure mode this whole action exists to avoid.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              complete
                  ? l10n.settingsRequestsWipeDone
                  : l10n.settingsRequestsWipeFailed,
            ),
          ),
        );
      },
    );
  }
}
