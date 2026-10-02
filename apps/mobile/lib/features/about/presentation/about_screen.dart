// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../l10n/l10n.dart';

/// Version information the About screen shows.
class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

/// Reads the bundled version metadata. Overridden in tests.
final FutureProvider<AppVersionInfo> appVersionProvider =
    FutureProvider<AppVersionInfo>((Ref ref) async {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return AppVersionInfo(
        version: info.version,
        buildNumber: info.buildNumber,
      );
    });

/// About screen: identity, licence, copyright and the binding independence
/// notice.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<AppVersionInfo> version = ref.watch(appVersionProvider);

    return ScreenScaffold(
      eyebrow: ModuleCategory.app.label(l10n),
      title: l10n.aboutTitle,
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: context.metrics.screenPadding,
        ),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          // The one screen that shows the app's own mark. Everywhere else the
          // brand is carried by the type and the rules; here it is the subject.
          const BrandWordmark(),
          const SizedBox(height: AppSpacing.md),
          // A version is a code, so it is set in the data face. Always
          // rendered: the line used to vanish without a word if the package
          // info could not be read, which shifts the layout and — on the one
          // screen a support request quotes from — leaves nothing to quote.
          Text(
            version.hasValue
                ? l10n.aboutVersion(
                    version.requireValue.version,
                    version.requireValue.buildNumber,
                  )
                : l10n.aboutVersionUnavailable,
            style: context.type.data,
          ),
          const SizedBox(height: AppSpacing.xl),
          StatusBanner(
            icon: AppIcons.info_outline,
            title: l10n.aboutIndependenceTitle,
            message: l10n.aboutIndependenceNotice,
          ),
          SectionHeader(
            label: l10n.aboutLicenseLabel,
            padding: const EdgeInsets.only(
              top: AppSpacing.xl,
              bottom: AppSpacing.sm,
            ),
          ),
          Text(l10n.aboutLicenseValue, style: text.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.aboutCopyright, style: text.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.aboutFontNotice, style: text.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationIcon: const BrandMark(size: 64),
                applicationLegalese: l10n.aboutCopyright,
                applicationVersion: version.hasValue
                    ? version.requireValue.version
                    : null,
              ),
              icon: const Icon(AppIcons.description_outlined),
              label: Text(l10n.aboutOpenSourceLicenses),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
