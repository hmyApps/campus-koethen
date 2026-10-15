// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/background/foreground_bridge.dart';
import 'background_sync_entrypoint.dart';
import 'background_sync_providers.dart';

/// Keeps the periodic background job registered while it is wanted, and lets
/// a background run that starts inside this process borrow the app's own
/// providers instead of opening the encrypted caches a second time.
class BackgroundSyncHost extends ConsumerStatefulWidget {
  const BackgroundSyncHost({required this.child, this.onRun, super.key});

  final Widget child;

  /// What a handed-over background run does. Defaults to the real run; a
  /// test replaces it so no step touches a network.
  @visibleForTesting
  final Future<void> Function(ProviderContainer container)? onRun;

  @override
  ConsumerState<BackgroundSyncHost> createState() => _BackgroundSyncHostState();
}

class _BackgroundSyncHostState extends ConsumerState<BackgroundSyncHost> {
  bool? _applied;

  @override
  void initState() {
    super.initState();
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    ForegroundBridge.register(
      () =>
          widget.onRun?.call(container) ??
          performBackgroundSync(container, ownsNotifications: false),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _apply(ref.read(backgroundSyncWantedProvider));
    });
  }

  @override
  void dispose() {
    ForegroundBridge.unregister();
    super.dispose();
  }

  void _apply(bool? wanted) {
    if (wanted == null || wanted == _applied) return;
    _applied = wanted;
    unawaited(ref.read(backgroundSyncSchedulerProvider).apply(wanted: wanted));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool?>(
      backgroundSyncWantedProvider,
      (bool? _, bool? wanted) => _apply(wanted),
    );
    return widget.child;
  }
}
