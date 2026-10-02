// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/domain/direct_service.dart';
import '../application/university_account_controller.dart';
import '../application/university_service_connector.dart';

/// Wraps a service's own setup screen so navigating to it behaves exactly
/// like the Settings "university access" card's own `+`: when a central
/// identity is already stored, it is used immediately and no second,
/// redundant credential form is ever shown. [builder] (the manual form) is
/// reached only when there is no stored identity yet, or when the stored one
/// was rejected — in which case [builder] receives the failure so it can
/// explain what happened.
class UniversityIdentityAutoConnect extends ConsumerStatefulWidget {
  const UniversityIdentityAutoConnect({
    required this.service,
    required this.builder,
    super.key,
  });

  final DirectService service;
  final Widget Function(BuildContext context, Object? autoConnectError) builder;

  @override
  ConsumerState<UniversityIdentityAutoConnect> createState() =>
      _UniversityIdentityAutoConnectState();
}

class _UniversityIdentityAutoConnectState
    extends ConsumerState<UniversityIdentityAutoConnect> {
  bool _attempted = false;
  bool _connecting = false;
  Object? _error;

  Future<void> _autoConnect() async {
    try {
      await ref
          .read(universityServiceConnectorProvider)
          .connect(widget.service);
      // On success the screen that renders this widget (e.g. `MoodleScreen`)
      // switches away from it on its own, once the service's own controller
      // reports "connected" — nothing left to do here.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<UniversityAccountState> account = ref.watch(
      universityAccountControllerProvider,
    );
    const Widget spinner = Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
    return account.when(
      loading: () => spinner,
      // A read failure is treated the same as "nothing stored yet": the
      // manual form still works, which matters more than blocking on a
      // convenience feature's own storage problem.
      error: (Object _, _) => widget.builder(context, null),
      data: (UniversityAccountState state) {
        if (state.hasIdentity && !_attempted) {
          _attempted = true;
          _connecting = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_autoConnect());
          });
        }
        if (_connecting) return spinner;
        return widget.builder(context, _error);
      },
    );
  }
}
