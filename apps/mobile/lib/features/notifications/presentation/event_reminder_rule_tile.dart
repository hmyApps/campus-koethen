// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../calendar/domain/calendar_entry.dart';
import '../application/notification_settings_controller.dart';

const int _useDefault = -2;
const int _disabled = -1;

class EventReminderRuleTile extends ConsumerWidget {
  const EventReminderRuleTile({required this.entry, super.key});

  final CalendarEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(notificationSettingsProvider);
    final int selected =
        preferences.eventReminderOverrides[entry.id] ?? _useDefault;
    return _ReminderDropdown(
      title: context.l10n.notificationEventRuleTitle,
      value: selected,
      includeDefault: true,
      defaultMinutes: preferences.eventReminderMinutes,
      onChanged: (value) => ref
          .read(notificationSettingsProvider.notifier)
          .setEventReminderOverride(
            entry.id,
            value == _useDefault ? null : value,
          ),
    );
  }
}

class EventReminderDefaultLeadTile extends ConsumerWidget {
  const EventReminderDefaultLeadTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int selected = ref
        .watch(notificationSettingsProvider)
        .eventReminderMinutes;
    return _ReminderDropdown(
      title: context.l10n.notificationEventDefaultLeadTitle,
      value: selected,
      includeDefault: false,
      defaultMinutes: selected,
      onChanged: (value) => ref
          .read(notificationSettingsProvider.notifier)
          .setEventReminderMinutes(value),
    );
  }
}

class _ReminderDropdown extends StatelessWidget {
  const _ReminderDropdown({
    required this.title,
    required this.value,
    required this.includeDefault,
    required this.defaultMinutes,
    required this.onChanged,
  });

  final String title;
  final int value;
  final bool includeDefault;
  final int defaultMinutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: Icon(AppIcons.notifications_outlined),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<int>(
                  initialValue: value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.notificationEventRuleLeadLabel,
                  ),
                  items: <DropdownMenuItem<int>>[
                    if (includeDefault)
                      DropdownMenuItem<int>(
                        value: _useDefault,
                        child: Text(
                          l10n.notificationEventRuleDefault(
                            reminderLeadLabel(l10n, defaultMinutes),
                          ),
                        ),
                      ),
                    if (includeDefault)
                      DropdownMenuItem<int>(
                        value: _disabled,
                        child: Text(l10n.notificationEventRuleOff),
                      ),
                    for (final int minutes
                        in NotificationSettingsController
                            .allowedEventReminderMinutes)
                      DropdownMenuItem<int>(
                        value: minutes,
                        child: Text(reminderLeadLabel(l10n, minutes)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onChanged(value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String reminderLeadLabel(AppLocalizations l10n, int minutes) =>
    switch (minutes) {
      15 => l10n.notificationLead15Minutes,
      60 => l10n.notificationLead1Hour,
      360 => l10n.notificationLead6Hours,
      1440 => l10n.notificationLead1Day,
      2880 => l10n.notificationLead2Days,
      10080 => l10n.notificationLead1Week,
      _ => l10n.notificationLead1Day,
    };
