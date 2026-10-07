// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';

/// Dedicated consent screen for connecting HSA-GPT outside the first-run
/// wizard — e.g. from the university-account card's `+` button, reached via
/// [connectHsaKiWithOnboarding]. The first-run wizard itself
/// (`OnboardingUniversityServicesStep`) shows a condensed inline version of
/// this same explanation next to its own checkbox instead of pushing this
/// screen, but the content — what HSA-GPT is, that the device talks straight
/// to `ki.hs-anhalt.de`, that only a revocable token is kept — is the same
/// either way.
class HsaKiOnboardingScreen extends StatelessWidget {
  const HsaKiOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Spacer(),
                  CloseButton(
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        AppIcons.message_2,
                        size: AppSizes.illustrationIcon,
                        color: colors.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(l10n.hsaKiOnboardingTitle, style: text.headlineMedium),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.hsaKiOnboardingIntro, style: text.bodyMedium),
                      const SizedBox(height: AppSpacing.lg),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(
                                    AppIcons.privacy_tip_outlined,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      l10n.hsaKiOnboardingPrivacyTitle,
                                      style: text.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                l10n.hsaKiOnboardingPrivacyBody,
                                style: text.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(AppIcons.warning_amber_outlined, color: colors.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              l10n.hsaKiOnboardingDisclaimer,
                              style: text.bodyMedium?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.hsaKiOnboardingContinue),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.hsaKiOnboardingCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pushes [HsaKiOnboardingScreen] and resolves to whether the user chose to
/// continue — `false` on every dismissal path (close button, cancel, back).
Future<bool> showHsaKiOnboardingScreen(BuildContext context) async {
  final bool? result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (BuildContext _) => const HsaKiOnboardingScreen(),
      fullscreenDialog: true,
    ),
  );
  return result ?? false;
}
