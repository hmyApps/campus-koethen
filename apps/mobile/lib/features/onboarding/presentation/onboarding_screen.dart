// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_routes.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/l10n.dart';
import '../../notifications/application/notification_providers.dart';
import '../../notifications/application/notification_settings_controller.dart';
import '../../notifications/domain/notification_permission.dart';
import '../../university_account/domain/university_identity.dart';
import 'onboarding_steps.dart';

/// First-run setup.
///
/// Every step is optional. Nothing here is a gate: a step whose backend source
/// is unavailable — no canteens published yet, no timetable groups synced —
/// says so and moves on, because a student who cannot finish the setup cannot
/// use the app at all.
///
/// Skipping counts as answering. The completion flag is set whether the user
/// walks through the steps or presses "skip all", so the app never asks twice
/// unprompted; restarting the setup is an explicit action in the settings.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _notificationsEnabled = true;
  String _universityIdentifier = '';
  String _universityPassword = '';
  bool _universityStorageConsent = false;
  bool _embeddedServiceBusy = false;
  bool _finishing = false;

  bool get _navigationLocked => _embeddedServiceBusy || _finishing;

  static const List<OnboardingStep> _steps = <OnboardingStep>[
    OnboardingStep.language,
    OnboardingStep.welcome,
    OnboardingStep.campus,
    OnboardingStep.content,
    OnboardingStep.calendar,
    OnboardingStep.universityAccess,
    OnboardingStep.universityServices,
    OnboardingStep.notifications,
  ];

  UniversityIdentity? get _pendingUniversityIdentity {
    if (!_universityStorageConsent) return null;
    final UniversityIdentity identity = UniversityIdentity(
      identifier: _universityIdentifier,
      password: _universityPassword,
    ).normalized;
    return identity.isValid ? identity : null;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({bool applyNotificationChoice = false}) async {
    if (_navigationLocked) return;
    setState(() => _finishing = true);
    try {
      if (applyNotificationChoice) {
        await _applyNotificationChoice();
      }
      TextInput.finishAutofillContext();
      _universityPassword = '';
      await ref.read(settingsProvider.notifier).setOnboardingCompleted(true);
      if (!mounted) return;
      GoRouter.of(context).go(AppRoutes.news);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _applyNotificationChoice() async {
    final notificationSettings = ref.read(
      notificationSettingsProvider.notifier,
    );
    if (!_notificationsEnabled) {
      await notificationSettings.setOptedIn(false);
      return;
    }

    final permissionController = ref.read(
      notificationPermissionProvider.notifier,
    );
    final NotificationPermissionStatus current = await permissionController
        .currentStatus();
    final NotificationPermissionStatus result = current.canPrompt
        ? await permissionController.request()
        : current;
    await notificationSettings.setOptedIn(result.allowsDelivery);
  }

  void _goTo(int index) {
    if (_navigationLocked || index < 0 || index >= _steps.length) return;
    setState(() => _index = index);
    // Reduced motion means no motion here either — the tokens already know.
    final AppMotion motion = context.motion;
    if (motion.reduced) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(index, duration: motion.medium, curve: motion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppMetrics metrics = context.metrics;
    final bool isLast = _index == _steps.length - 1;

    return PopScope(
      canPop: !_navigationLocked,
      child: Scaffold(
        // The step counter lives in the body, right above the bar it describes:
        // "Schritt 5 von 5" and "Alles überspringen" cannot share an app bar on
        // a 320 px phone with scaled text. The action itself collapses to an
        // icon at that point, keeping its tooltip and accessible name.
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          actions: <Widget>[
            if (MediaQuery.textScalerOf(context).scale(14) > 20)
              IconButton(
                onPressed: _navigationLocked ? null : () => _finish(),
                tooltip: l10n.onboardingSkipAll,
                icon: const Icon(AppIcons.skip_next_outlined),
              )
            else
              TextButton(
                onPressed: _navigationLocked ? null : () => _finish(),
                child: Text(l10n.onboardingSkipAll),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.screenPadding,
                  0,
                  metrics.screenPadding,
                  AppSpacing.xs,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  // "Schritt 2 von 5" is a count, so it is set in the data face.
                  child: Text(
                    l10n.onboardingStepOf(_index + 1, _steps.length),
                    style: context.type.dataSmall,
                  ),
                ),
              ),
              // How far you are is a live state, so the bar is the marker — the
              // same stroke the navigation puts under the tab you are on.
              LinearProgressIndicator(
                value: (_index + 1) / _steps.length,
                minHeight: AppSizes.beam,
                color: context.colors.accent,
                backgroundColor: context.colors.surfaceVariant,
                semanticsLabel: l10n.onboardingStepOf(
                  _index + 1,
                  _steps.length,
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  // Driven by the buttons only: a half-finished swipe on a
                  // setup flow makes it unclear which step you are answering.
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _steps.length,
                  itemBuilder: (BuildContext context, int index) => Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.screenPadding,
                    ),
                    child: OnboardingStepView(
                      step: _steps[index],
                      notificationsEnabled: _notificationsEnabled,
                      universityIdentifier: _universityIdentifier,
                      universityPassword: _universityPassword,
                      universityStorageConsent: _universityStorageConsent,
                      pendingUniversityIdentity: _pendingUniversityIdentity,
                      onNotificationsEnabledChanged: (bool value) {
                        setState(() => _notificationsEnabled = value);
                      },
                      onUniversityIdentifierChanged: (String value) {
                        setState(() => _universityIdentifier = value);
                      },
                      onUniversityPasswordChanged: (String value) {
                        setState(() => _universityPassword = value);
                      },
                      onUniversityStorageConsentChanged: (bool value) {
                        setState(() => _universityStorageConsent = value);
                      },
                      onUniversityServicesBusyChanged: (bool value) {
                        if (!mounted || _embeddedServiceBusy == value) return;
                        setState(() => _embeddedServiceBusy = value);
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(metrics.screenPadding),
                // OverflowBar, not a Row: three labelled buttons do not fit
                // beside each other on a narrow phone, let alone with scaled
                // text. It lays out horizontally while there is room and stacks
                // when there is not, instead of overflowing.
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: AppSpacing.sm,
                  overflowSpacing: AppSpacing.xs,
                  children: <Widget>[
                    if (_index > 0)
                      TextButton(
                        onPressed: _navigationLocked
                            ? null
                            : () => _goTo(_index - 1),
                        child: Text(l10n.onboardingBack),
                      ),
                    if (!isLast)
                      TextButton(
                        onPressed: _navigationLocked
                            ? null
                            : () => _goTo(_index + 1),
                        child: Text(l10n.onboardingSkip),
                      ),
                    FilledButton(
                      onPressed: _navigationLocked
                          ? null
                          : isLast
                          ? () => _finish(applyNotificationChoice: true)
                          : () => _goTo(_index + 1),
                      child: _finishing
                          ? Semantics(
                              liveRegion: true,
                              label: l10n.commonLoadingSemanticLabel,
                              child: const ExcludeSemantics(
                                child: SizedBox.square(
                                  dimension: AppSizes.iconSmall,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : Text(l10n.onboardingNext),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
