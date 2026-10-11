// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/links/safe_link_launcher.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/network/network_providers.dart';
import 'package:campus_koethen/features/calendar/presentation/manage_calendars_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../support/fake_http_adapter.dart';
import '../../support/pump_app.dart';

Map<String, dynamic> calendarJson({
  required String slug,
  required String name,
  bool defaultSubscribed = true,
}) => <String, dynamic>{
  'id': 'id-$slug',
  'slug': slug,
  'name': name,
  'description': null,
  'colorHex': '#5B3FD0',
  'sortOrder': 0,
  'defaultSubscribed': defaultSubscribed,
  'dataState': 'ready',
  'dataStale': false,
  'lastSuccessfulSyncAt': '2026-06-10T00:00:00.000Z',
  'googleOpenUrl': 'https://calendar.google.com/calendar/render?cid=abc',
};

class _FakeLauncher implements SafeLinkLauncher {
  final List<String> opened = <String>[];
  @override
  Future<LinkLaunchResult> open(String? rawUrl) async {
    opened.add(rawUrl ?? '');
    return LinkLaunchResult.opened;
  }
}

FakeHttpAdapter _api({bool translationFallback = false}) => FakeHttpAdapter((
  RequestOptions options,
) {
  if (options.path.endsWith('/calendars/google-view-url')) {
    return FakeHttpResponse(
      envelope(<String, dynamic>{
        'url': 'https://calendar.google.com/calendar/embed?src=abc',
      }),
    );
  }
  if (options.path.endsWith('/calendars')) {
    return FakeHttpResponse(
      envelope(
        <Map<String, dynamic>>[
          calendarJson(slug: 'beispielkalender-a', name: 'Beispielkalender A'),
        ],
        meta: <String, dynamic>{'translationFallback': translationFallback},
      ),
    );
  }
  return const FakeHttpResponse('{}', statusCode: 404);
});

void main() {
  testWidgets('discloses a German fallback in the calendar catalogue', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      const ManageCalendarsScreen(),
      locale: AppLocales.english,
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          fakeApiClient(_api(translationFallback: true)),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('original German text'), findsOneWidget);
  });

  testWidgets('lists public calendars and opens the combined Google view', (
    WidgetTester tester,
  ) async {
    final _FakeLauncher launcher = _FakeLauncher();
    final FakeHttpAdapter adapter = _api();
    await pumpScreen(
      tester,
      const ManageCalendarsScreen(),
      overrides: <Override>[
        apiClientProvider.overrideWithValue(fakeApiClient(adapter)),
        linkLauncherProvider.overrideWithValue(launcher),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Beispielkalender A'), findsOneWidget);
    // defaultSubscribed → auto-selected → combined button enabled.
    expect(find.text('Ausgewählte in Google Kalender öffnen'), findsOneWidget);
    expect(
      find.textContaining('Nur öffentliche Google-Kalender'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ausgewählte in Google Kalender öffnen'));
    await tester.pumpAndSettle();

    expect(launcher.opened, hasLength(1));
    expect(
      launcher.opened.first,
      contains('calendar.google.com/calendar/embed'),
    );
    expect(
      adapter.requests.last.uri.query,
      contains('calendar=beispielkalender-a'),
    );
  });

  testWidgets('opens a single calendar in Google via its googleOpenUrl', (
    WidgetTester tester,
  ) async {
    final _FakeLauncher launcher = _FakeLauncher();
    await pumpScreen(
      tester,
      const ManageCalendarsScreen(),
      overrides: <Override>[
        apiClientProvider.overrideWithValue(fakeApiClient(_api())),
        linkLauncherProvider.overrideWithValue(launcher),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.open_in_new).first);
    await tester.pumpAndSettle();

    expect(launcher.opened.first, contains('calendar/render?cid=abc'));
  });
}
