// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/domain/direct_service.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../../university_account/presentation/university_account_setup_sheet.dart';
import 'hsa_ki_onboarding_screen.dart';

/// The one place that decides what happens after the user agrees to connect
/// HSA-GPT: the dedicated consent screen first, then either a direct connect
/// (the central identity is already stored) or the generic credential sheet
/// (it is not yet). Shared by the chat screen's own "not connected" prompt
/// and the university-account card's `+`, so both entry points behave
/// identically.
///
/// Returns `true` once a connection attempt actually happened (whether or not
/// it ultimately raised), `false` if the user never got past the consent
/// screen. Callers remain responsible for catching a connect failure the way
/// every other direct service's toggle already does.
Future<bool> connectHsaKiWithOnboarding(
  BuildContext context,
  WidgetRef ref,
) async {
  final bool proceed = await showHsaKiOnboardingScreen(context);
  if (!proceed || !context.mounted) return false;

  final bool hasIdentity =
      ref.read(universityAccountControllerProvider).value?.hasIdentity ?? false;
  if (!hasIdentity) {
    await showUniversityAccountSetupSheet(
      context,
      initialService: DirectService.hsaKi,
    );
    return true;
  }
  await ref
      .read(universityServiceConnectorProvider)
      .connect(DirectService.hsaKi);
  return true;
}
