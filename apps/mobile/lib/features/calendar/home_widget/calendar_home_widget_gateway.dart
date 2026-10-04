// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'calendar_home_widget_payload.dart';

const String calendarHomeWidgetAppGroup = 'group.dev.erikengler.campuskoethen';
const String calendarHomeWidgetPayloadKey = 'calendar_widget_payload';
const String calendarHomeWidgetAndroidName = 'CalendarWidgetProvider';
const String calendarHomeWidgetQualifiedAndroidName =
    'dev.erikengler.campuskoethen.CalendarWidgetProvider';
const String calendarHomeWidgetIosName = 'CampusCalendarWidget';

abstract interface class CalendarHomeWidgetGateway {
  Stream<Uri?> get clicks;
  Future<Uri?> initiallyLaunchedFromWidget();
  Future<void> sync(CalendarHomeWidgetPayload payload);
  Future<bool> canRequestPin();
  Future<void> requestPin();
}

class PlatformCalendarHomeWidgetGateway implements CalendarHomeWidgetGateway {
  const PlatformCalendarHomeWidgetGateway();

  @override
  Stream<Uri?> get clicks => HomeWidget.widgetClicked;

  @override
  Future<Uri?> initiallyLaunchedFromWidget() =>
      HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Future<void> sync(CalendarHomeWidgetPayload payload) async {
    await HomeWidget.setAppGroupId(calendarHomeWidgetAppGroup);
    final bool? saved = await HomeWidget.saveWidgetData<String>(
      calendarHomeWidgetPayloadKey,
      jsonEncode(payload.toJson()),
      appGroupId: calendarHomeWidgetAppGroup,
    );
    if (saved != true) throw const CalendarHomeWidgetUnavailable();
    await HomeWidget.updateWidget(
      androidName: calendarHomeWidgetAndroidName,
      qualifiedAndroidName: calendarHomeWidgetQualifiedAndroidName,
      iOSName: calendarHomeWidgetIosName,
    );
  }

  @override
  Future<bool> canRequestPin() async =>
      await HomeWidget.isRequestPinWidgetSupported() ?? false;

  @override
  Future<void> requestPin() => HomeWidget.requestPinWidget(
    androidName: calendarHomeWidgetAndroidName,
    qualifiedAndroidName: calendarHomeWidgetQualifiedAndroidName,
  );
}

class CalendarHomeWidgetUnavailable implements Exception {
  const CalendarHomeWidgetUnavailable();
}

final Provider<CalendarHomeWidgetGateway> calendarHomeWidgetGatewayProvider =
    Provider<CalendarHomeWidgetGateway>(
      (Ref ref) => const PlatformCalendarHomeWidgetGateway(),
    );

bool isCalendarHomeWidgetLaunch(Uri? uri) =>
    uri != null &&
    uri.scheme == 'campuskoethen' &&
    uri.host == 'calendar' &&
    uri.queryParameters.containsKey('homeWidget');
