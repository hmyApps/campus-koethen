// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../l10n/l10n.dart';
import 'calendar_home_widget_gateway.dart';
import 'calendar_home_widget_settings.dart';

class CalendarHomeWidgetSettingsScreen extends ConsumerStatefulWidget {
  const CalendarHomeWidgetSettingsScreen({super.key});

  @override
  ConsumerState<CalendarHomeWidgetSettingsScreen> createState() =>
      _CalendarHomeWidgetSettingsScreenState();
}

class _CalendarHomeWidgetSettingsScreenState
    extends ConsumerState<CalendarHomeWidgetSettingsScreen> {
  bool _requesting = false;

  Future<void> _requestPin() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final AppLocalizations l10n = context.l10n;
    try {
      final CalendarHomeWidgetGateway gateway = ref.read(
        calendarHomeWidgetGatewayProvider,
      );
      if (!await gateway.canRequestPin()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.calendarHomeWidgetAddAndroidUnavailable)),
        );
        return;
      }
      await gateway.requestPin();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.calendarHomeWidgetAddRequested)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.calendarHomeWidgetUnavailable)),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final CalendarHomeWidgetSettings settings = ref.watch(
      calendarHomeWidgetSettingsProvider,
    );
    final TargetPlatform platform = defaultTargetPlatform;
    return ScreenScaffold(
      title: l10n.calendarHomeWidgetTitle,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: <Widget>[
          SwitchListTile(
            secondary: const Icon(AppIcons.calendar_month_outlined),
            title: Text(l10n.calendarHomeWidgetEnable),
            subtitle: Text(l10n.calendarHomeWidgetEnableSubtitle),
            value: settings.enabled,
            onChanged: (bool value) => ref
                .read(calendarHomeWidgetSettingsProvider.notifier)
                .setEnabled(value),
          ),
          SwitchListTile(
            secondary: const Icon(AppIcons.visibility_outlined),
            title: Text(l10n.calendarHomeWidgetShowDetails),
            subtitle: Text(l10n.calendarHomeWidgetShowDetailsSubtitle),
            value: settings.showDetails,
            onChanged: settings.enabled
                ? (bool value) => ref
                      .read(calendarHomeWidgetSettingsProvider.notifier)
                      .setShowDetails(value)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Semantics(
              readOnly: true,
              child: Text(l10n.calendarHomeWidgetPrivacyNotice),
            ),
          ),
          if (settings.enabled && platform == TargetPlatform.android)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: FilledButton.icon(
                onPressed: _requesting ? null : _requestPin,
                icon: const Icon(AppIcons.add),
                label: Text(l10n.calendarHomeWidgetAddAndroid),
              ),
            ),
          if (settings.enabled && platform == TargetPlatform.iOS)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(l10n.calendarHomeWidgetAddIos),
            ),
        ],
      ),
    );
  }
}
