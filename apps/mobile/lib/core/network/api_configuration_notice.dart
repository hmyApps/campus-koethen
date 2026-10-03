// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../l10n/l10n.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_metrics.dart';
import '../widgets/status_banner.dart';
import 'api_config.dart';

/// This build's Campus API configuration problem, if any.
///
/// A provider rather than a direct read of the compile-time constant, so both
/// states are reachable in a widget test — the same reasoning as
/// `requestsEndpointConfiguredProvider`.
final Provider<ApiConfigProblem?> apiConfigurationProblemProvider =
    Provider<ApiConfigProblem?>((Ref ref) => ApiConfig.configurationProblem);

/// Whether [problem] is worth putting in front of the reader.
///
/// `notConfigured` means the build still points at `http://localhost:3000` —
/// which is the documented local development setup, not a defect, and a
/// permanent banner over every screen of every debug run would be noise. In a
/// **release** build the same state means the app was shipped without an
/// endpoint and cannot load anything, which is worth saying loudly.
///
/// The other two — a malformed address, or plain HTTP to something that is not
/// loopback — are wrong in every build.
bool shouldShowApiConfigurationNotice(ApiConfigProblem? problem) =>
    switch (problem) {
      null => false,
      ApiConfigProblem.notConfigured => kReleaseMode,
      ApiConfigProblem.malformed || ApiConfigProblem.insecureScheme => true,
    };

/// Says out loud that this build cannot reach the Campus API.
///
/// Without it an unconfigured or plaintext build simply failed at every
/// campus screen: the platform's own cleartext rules block the request, so the
/// symptom was a total outage with no cause on screen (S-11). The requests
/// feature has always shown its equivalent of this banner.
class ApiConfigurationNotice extends ConsumerWidget {
  const ApiConfigurationNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ApiConfigProblem? problem = ref.watch(
      apiConfigurationProblemProvider,
    );
    if (!shouldShowApiConfigurationNotice(problem)) {
      return const SizedBox.shrink();
    }

    final AppLocalizations l10n = context.l10n;
    final (String title, String message) = switch (problem!) {
      ApiConfigProblem.notConfigured => (
        l10n.apiNotConfiguredTitle,
        l10n.apiNotConfiguredBody,
      ),
      // Both remaining cases are "this address will not be used": a malformed
      // URL and a plaintext one fail for different reasons and look identical
      // to the reader, who can act on neither.
      ApiConfigProblem.malformed || ApiConfigProblem.insecureScheme => (
        l10n.apiInsecureTitle,
        l10n.apiInsecureBody,
      ),
    };

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.metrics.screenPadding,
          AppSpacing.sm,
          context.metrics.screenPadding,
          0,
        ),
        child: StatusBanner(
          tone: StatusTone.warning,
          icon: AppIcons.cloud_off_outlined,
          title: title,
          message: message,
          liveRegion: true,
        ),
      ),
    );
  }
}
