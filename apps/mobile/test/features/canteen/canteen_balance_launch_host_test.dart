// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/app/app_router.dart';
import 'package:campus_koethen/app/app_routes.dart';
import 'package:campus_koethen/features/canteen/application/canteen_balance_providers.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_balance_apdu.dart';
import 'package:campus_koethen/features/canteen/domain/canteen_balance_reader.dart';
import 'package:campus_koethen/features/canteen/presentation/canteen_balance_launch_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _LaunchReader implements CanteenBalanceReader {
  _LaunchReader({this.pending = false});

  bool pending;
  final StreamController<void> events = StreamController<void>.broadcast();

  @override
  Future<CanteenBalanceAvailability> availability() async =>
      CanteenBalanceAvailability.available;

  @override
  Stream<void> get externalTagDiscovered => events.stream;

  @override
  Future<bool> hasPendingExternalTag() async => pending;

  @override
  Future<CanteenBalance> read({
    required CanteenBalanceReadOrigin origin,
    required String prompt,
  }) => throw UnimplementedError();

  @override
  Future<void> cancel() async {}
}

Future<GoRouter> _pumpHost(WidgetTester tester, _LaunchReader reader) async {
  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const Text('home')),
      GoRoute(
        path: AppRoutes.canteen,
        builder: (_, _) => const Text('canteen'),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(reader.events.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appRouterProvider.overrideWithValue(router),
        canteenBalanceReaderProvider.overrideWithValue(reader),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) =>
            CanteenBalanceLaunchHost(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  testWidgets('cold-start pending tag routes to one external balance launch', (
    WidgetTester tester,
  ) async {
    final _LaunchReader reader = _LaunchReader(pending: true);
    final GoRouter router = await _pumpHost(tester, reader);
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.queryParameters,
      containsPair(AppRoutes.canteenBalanceParam, 'external'),
    );
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.canteen);
  });

  testWidgets('a new Android tag changes the launch token on the same route', (
    WidgetTester tester,
  ) async {
    final _LaunchReader reader = _LaunchReader();
    final GoRouter router = await _pumpHost(tester, reader);

    reader.events.add(null);
    await tester.pump();
    final String? first = router
        .routeInformationProvider
        .value
        .uri
        .queryParameters[AppRoutes.canteenBalanceLaunchParam];

    reader.events.add(null);
    await tester.pump();
    final String? second = router
        .routeInformationProvider
        .value
        .uri
        .queryParameters[AppRoutes.canteenBalanceLaunchParam];

    expect(first, isNotNull);
    expect(second, isNot(first));
  });
}
