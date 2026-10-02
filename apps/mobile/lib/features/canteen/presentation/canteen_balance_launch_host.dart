// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_router.dart';
import '../../../app/app_routes.dart';
import '../application/canteen_balance_providers.dart';
import '../domain/canteen_balance_reader.dart';

/// Routes Android TECH_DISCOVERED events to the canteen balance surface.
///
/// The stream deliberately carries `void`: no UID, balance or raw tag object
/// crosses into application navigation. A cold-start intent is recovered by
/// [hasPendingExternalTag] after the Flutter channel becomes ready.
class CanteenBalanceLaunchHost extends ConsumerStatefulWidget {
  const CanteenBalanceLaunchHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CanteenBalanceLaunchHost> createState() =>
      _CanteenBalanceLaunchHostState();
}

class _CanteenBalanceLaunchHostState
    extends ConsumerState<CanteenBalanceLaunchHost> {
  StreamSubscription<void>? _subscription;
  late final CanteenBalanceReader _reader;
  int _launch = 0;

  @override
  void initState() {
    super.initState();
    _reader = ref.read(canteenBalanceReaderProvider);
    _subscription = _reader.externalTagDiscovered.listen((_) => _open());
    unawaited(_openPendingTag());
  }

  Future<void> _openPendingTag() async {
    try {
      if (await _reader.hasPendingExternalTag()) _open();
    } catch (_) {
      // Missing/disabled NFC is represented in the sheet when requested.
      // Startup must remain unaffected on unsupported platforms.
    }
  }

  void _open() {
    if (!mounted) return;
    _launch += 1;
    ref
        .read(appRouterProvider)
        .go(AppRoutes.canteenExternalBalanceLocation(_launch));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
