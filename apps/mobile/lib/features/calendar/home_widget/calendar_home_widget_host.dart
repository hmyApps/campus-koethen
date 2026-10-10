// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_router.dart';
import '../../../app/app_routes.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_entry.dart';
import 'calendar_home_widget_gateway.dart';
import 'calendar_home_widget_payload.dart';
import 'calendar_home_widget_settings.dart';

/// Whether [data] may replace the payload the OS home widget last persisted.
///
/// * A source still **loading without data** holds the sync back: it answers
///   in a moment, and syncing now would only blank its entries in between.
/// * A **failed** source does not recover by waiting. Holding back on any
///   error froze the widget for good behind, for example, a connected Moodle
///   account without a course cache whose sync keeps failing (F-07). The
///   entries that are there are synced; only a failure with nothing to show
///   keeps the last payload.
///
/// Exchange appointments never reach the widget payload, so they never count
/// as something to show.
bool calendarHomeWidgetMaySync(CalendarData data) {
  bool hasEntriesOf(CalendarSource source) =>
      data.entries.any((CalendarEntry entry) => entry.source == source);

  if ((data.timetableLoading && !hasEntriesOf(CalendarSource.timetable)) ||
      (data.moodleLoading && !hasEntriesOf(CalendarSource.moodle)) ||
      (data.publicCalendarsLoading &&
          !hasEntriesOf(CalendarSource.publicCalendar))) {
    return false;
  }
  final bool anySourceFailed =
      data.hasTimetableError ||
      data.hasMoodleError ||
      data.hasPublicCalendarError;
  return !anySourceFailed ||
      data.entries.any(
        (CalendarEntry entry) =>
            entry.source != CalendarSource.exchangeCalendar,
      );
}

class CalendarHomeWidgetHost extends ConsumerStatefulWidget {
  const CalendarHomeWidgetHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CalendarHomeWidgetHost> createState() =>
      _CalendarHomeWidgetHostState();
}

class _CalendarHomeWidgetHostState extends ConsumerState<CalendarHomeWidgetHost>
    with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _clicks;
  String? _lastSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final CalendarHomeWidgetGateway gateway = ref.read(
      calendarHomeWidgetGatewayProvider,
    );
    _clicks = gateway.clicks.listen(
      _openCalendarIfValid,
      onError: (_) {
        // The platform channel does not exist on unsupported targets and in
        // widget tests. The normal in-app calendar remains available.
      },
    );
    unawaited(_readInitialLaunch(gateway));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_clicks?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastSignature = null;
      if (mounted) setState(() {});
    }
  }

  void _openCalendarIfValid(Uri? uri) {
    if (!isCalendarHomeWidgetLaunch(uri)) return;
    ref.read(appRouterProvider).go(AppRoutes.calendar);
  }

  Future<void> _readInitialLaunch(CalendarHomeWidgetGateway gateway) async {
    try {
      _openCalendarIfValid(await gateway.initiallyLaunchedFromWidget());
    } catch (_) {
      // The platform channel is optional outside Android and iOS.
    }
  }

  void _sync(CalendarHomeWidgetPayload payload, String signature) {
    if (_lastSignature == signature) return;
    _lastSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await ref.read(calendarHomeWidgetGatewayProvider).sync(payload);
      } catch (_) {
        // The app remains fully usable when the OS widget service or iOS App
        // Group is unavailable. Settings explains the manual platform setup.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final CalendarHomeWidgetSettings settings = ref.watch(
      calendarHomeWidgetSettingsProvider,
    );
    final String locale = Localizations.localeOf(context).languageCode;
    final DateTime now = DateTime.now();
    if (!settings.enabled) {
      const String signature = 'disabled';
      _sync(
        CalendarHomeWidgetPayload.disabled(now: now, locale: locale),
        signature,
      );
      return widget.child;
    }

    final CalendarData data = ref.watch(calendarListDataProvider(now));
    if (calendarHomeWidgetMaySync(data)) {
      final CalendarHomeWidgetPayload payload = buildCalendarHomeWidgetPayload(
        entries: data.entries,
        now: now,
        locale: locale,
        showDetails: settings.showDetails,
      );
      final String signature = jsonEncode(<String, Object?>{
        'locale': payload.locale,
        'details': payload.showDetails,
        'events': payload.events
            .map((CalendarHomeWidgetEvent event) => event.toJson())
            .toList(growable: false),
      });
      _sync(payload, signature);
    }
    return widget.child;
  }
}
