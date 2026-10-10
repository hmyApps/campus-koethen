// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/domain/direct_service.dart';
import '../../university_account/application/university_account_controller.dart';
import '../../university_account/application/university_service_connector.dart';
import '../../university_account/domain/university_identity.dart';
import '../../university_account/presentation/university_account_setup_sheet.dart';
import '../application/hsa_ki_consent.dart';
import 'hsa_ki_onboarding_screen.dart';

/// The one place that decides what happens after the user agrees to connect
/// HSA-GPT: the dedicated consent screen first, then either a direct connect
/// (the central identity is already stored), the first-run wizard's still
/// unsaved [draft] (validated by HAWKI before it is retained), or the generic
/// credential sheet. Shared by the chat screen's own "not connected" prompt,
/// the university-account card's `+` and the first-run wizard, so every entry
/// point behaves identically (`AGENTS.md` §2).
///
/// Only the steps after a positive answer run inside the consent scope of
/// [HsaKiConsentGate]; the HSA-GPT adapter refuses every token mint outside
/// of it, so no other generic path can connect HSA-GPT silently.
///
/// Returns `true` once a connection attempt actually happened (whether or not
/// it ultimately raised), `false` if the user never got past the consent
/// screen. Callers remain responsible for catching a connect failure the way
/// every other direct service's toggle already does.
Future<bool> connectHsaKiWithOnboarding(
  BuildContext context,
  WidgetRef ref, {
  UniversityIdentity? draft,
}) async {
  final bool proceed = await showHsaKiOnboardingScreen(context);
  if (!proceed || !context.mounted) return false;

  final HsaKiConsentGate consent = ref.read(hsaKiConsentGateProvider);
  final UniversityServiceConnector connector = ref.read(
    universityServiceConnectorProvider,
  );
  final bool hasIdentity =
      ref.read(universityAccountControllerProvider).value?.hasIdentity ?? false;
  await consent.runWithConsent<void>(() async {
    if (hasIdentity) {
      await connector.connect(DirectService.hsaKi);
    } else if (draft != null && draft.isValid) {
      await connector.connectAndRetain(DirectService.hsaKi, draft);
    } else {
      await showUniversityAccountSetupSheet(
        context,
        initialService: DirectService.hsaKi,
      );
    }
  });
  return true;
}
