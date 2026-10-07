// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_modules.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';
import '../application/notification_providers.dart';
import '../application/notification_settings_controller.dart';
import '../domain/notification_category.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_plan.dart';
import '../domain/notification_preferences.dart';
import 'pre_permission_sheet.dart';
import 'daily_summary_time_tile.dart';
import 'event_reminder_rule_tile.dart';

/// `/more/settings/notifications` — the one place where the whole feature can
/// be switched on, tuned and switched off again.
///
/// The screen has to be honest about a state it does not own: the operating
/// system's permission. A switch that says "on" while the system delivers
/// nothing is the single worst outcome here, so the permission is re-read
/// whenever the screen comes back into view and the categories are shown as
/// disabled when nothing can be delivered.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings is the whole point: the reader was
    // just sent there to change exactly this, and the banner has to disappear
    // without a restart (UX spec § 7, state 11).
    if (state != AppLifecycleState.resumed) return;
    ref.read(notificationPermissionProvider.notifier).refresh();
    ref.invalidate(mutedNotificationCategoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final NotificationPreferences preferences = ref.watch(
      notificationSettingsProvider,
    );
    final NotificationPermissionStatus permission =
        ref.watch(notificationPermissionProvider).value ??
        NotificationPermissionStatus.notDetermined;
    final Set<NotificationCategory> muted =
        ref.watch(mutedNotificationCategoriesProvider).value ??
        const <NotificationCategory>{};
    final NotificationPlan plan = ref.watch(notificationPlanProvider);

    final bool blocked = permission.needsSystemSettings;
    final bool categoriesInteractive = preferences.optedIn && !blocked;

    return ScreenScaffold(
      eyebrow: ModuleCategory.app.label(l10n),
      title: l10n.notificationsTitle,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: <Widget>[
          if (blocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: StatusBanner(
                title: l10n.notificationsPermissionBlockedTitle,
                message: l10n.notificationsPermissionBlockedMessage,
                tone: StatusTone.warning,
                icon: AppIcons.notifications_off_outlined,
                action: TextButton(
                  onPressed: () => ref
                      .read(notificationGatewayProvider)
                      .openSystemNotificationSettings(),
                  child: Text(l10n.notificationsOpenSystemSettings),
                ),
              ),
            ),
          _MasterSwitch(preferences: preferences, blocked: blocked),
          const DailySummaryTimeTile(),
          SectionHeader(label: l10n.notificationsSectionCategories),
          for (final NotificationCategory category
              in NotificationCategory.values) ...<Widget>[
            _CategorySwitch(
              category: category,
              enabled: preferences.isCategoryEnabled(category),
              interactive: categoriesInteractive,
              muted: muted.contains(category),
            ),
            if (category == NotificationCategory.eventReminder)
              const EventReminderDefaultLeadTile(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: StatusBanner(
              title: l10n.notificationsTimetableMoodleNoticeTitle,
              message: l10n.notificationsTimetableMoodleNotice,
              icon: AppIcons.school_outlined,
            ),
          ),
          SectionHeader(label: l10n.notificationsSectionStatus),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: StatusBanner(
              title: l10n.notificationsFreshnessTitle,
              message: l10n.notificationsFreshnessNotice,
              icon: AppIcons.info_outline,
            ),
          ),
          ListTile(
            leading: const Icon(AppIcons.schedule_outlined),
            title: Text(
              l10n.notificationsPendingCount(plan.notifications.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterSwitch extends ConsumerWidget {
  const _MasterSwitch({required this.preferences, required this.blocked});

  final NotificationPreferences preferences;
  final bool blocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    return _SemanticSwitchTile(
      icon: AppIcons.notifications_outlined,
      title: l10n.notificationsMasterSwitch,
      subtitle: l10n.notificationsMasterSwitchSubtitle,
      value: preferences.optedIn,
      // Switching **off** must stay possible even while the permission is
      // blocked: the reader is entitled to say "not this app" without first
      // going through a system settings detour.
      onChanged: (blocked && !preferences.optedIn)
          ? null
          : (bool value) async {
              if (!value) {
                await ref
                    .read(notificationSettingsProvider.notifier)
                    .setOptedIn(false);
                return;
              }
              if (!context.mounted) return;
              await requestNotificationOptIn(context, ref);
            },
    );
  }
}

class _CategorySwitch extends ConsumerWidget {
  const _CategorySwitch({
    required this.category,
    required this.enabled,
    required this.interactive,
    required this.muted,
  });

  final NotificationCategory category;
  final bool enabled;
  final bool interactive;
  final bool muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final (String title, String subtitle, IconData icon) = switch (category) {
      NotificationCategory.dailySummary => (
        l10n.notificationsCategoryDailySummary,
        l10n.notificationsCategoryDailySummarySubtitle,
        AppIcons.today_outlined,
      ),
      NotificationCategory.eventReminder => (
        l10n.notificationsCategoryEvents,
        l10n.notificationsCategoryEventsSubtitle,
        AppIcons.calendar_month_outlined,
      ),
      NotificationCategory.canteenFavourite => (
        l10n.notificationsCategoryCanteen,
        l10n.notificationsCategoryCanteenSubtitle,
        AppIcons.restaurant_outlined,
      ),
    };
    return _SemanticSwitchTile(
      icon: icon,
      title: title,
      // A silenced Android channel is not the app's doing and not something
      // the app can undo — but leaving the reader to wonder why one category
      // is quiet is worse than one extra line.
      subtitle: muted
          ? '$subtitle\n${l10n.notificationsCategoryMuted}'
          : subtitle,
      value: enabled,
      onChanged: interactive
          ? (bool value) => ref
                .read(notificationSettingsProvider.notifier)
                .setCategoryEnabled(category, value)
          : null,
    );
  }
}

/// A switch row that announces its own state and what a double tap will do.
///
/// `SwitchListTile` already exposes a toggle to the screen reader, but the
/// state it announces is the raw one; the spec asks for the label, the value
/// and the hint together (UX spec § 8.1).
class _SemanticSwitchTile extends StatelessWidget {
  const _SemanticSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Semantics(
      label: title,
      value: value
          ? l10n.notificationsSwitchStateOn
          : l10n.notificationsSwitchStateOff,
      hint: onChanged == null
          ? null
          : (value
                ? l10n.notificationsSwitchHintDisable
                : l10n.notificationsSwitchHintEnable),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
