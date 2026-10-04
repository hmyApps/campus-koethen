// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';

import '../../../app/app_modules.dart';
import '../../../core/links/linkified_text.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/widgets/screen_scaffold.dart';
import '../../../l10n/l10n.dart';

/// Which legal page to show.
enum LegalPage { imprint, privacy }

/// Complete, locally bundled legal notice and privacy policy.
///
/// Bundling the content keeps both pages available offline and ensures that
/// opening a legal page does not itself cause another network request.
class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.page, super.key});

  final LegalPage page;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final String title = switch (page) {
      LegalPage.imprint => l10n.imprintTitle,
      LegalPage.privacy => l10n.privacyTitle,
    };
    final List<_LegalSection> sections = switch (page) {
      LegalPage.imprint => <_LegalSection>[
        _LegalSection(l10n.imprintProviderTitle, l10n.imprintProviderBody),
        _LegalSection(
          l10n.imprintDevelopmentTitle,
          l10n.imprintDevelopmentBody,
        ),
        _LegalSection(l10n.imprintBackendTitle, l10n.imprintBackendBody),
        _LegalSection(l10n.imprintEditorialTitle, l10n.imprintEditorialBody),
        _LegalSection(l10n.imprintCopyrightTitle, l10n.imprintCopyrightBody),
        _LegalSection(
          l10n.aboutIndependenceTitle,
          l10n.aboutIndependenceNotice,
        ),
      ],
      LegalPage.privacy => <_LegalSection>[
        _LegalSection(l10n.privacyScopeTitle, l10n.privacyScopeBody),
        _LegalSection(l10n.privacyBackendTitle, l10n.privacyBackendBody),
        _LegalSection(
          l10n.privacyBackendStorageTitle,
          l10n.privacyBackendStorageBody,
        ),
        _LegalSection(l10n.privacyHostingTitle, l10n.privacyHostingBody),
        _LegalSection(l10n.privacyLocalTitle, l10n.privacyLocalBody),
        _LegalSection(
          l10n.privacyCalendarHomeWidgetTitle,
          l10n.privacyCalendarHomeWidgetBody,
        ),
        _LegalSection(
          l10n.privacyUniversityAccessTitle,
          l10n.privacyUniversityAccessBody,
        ),
        _LegalSection(l10n.privacyMailTitle, l10n.privacyMailBody),
        _LegalSection(l10n.privacyGradesTitle, l10n.privacyGradesBody),
        _LegalSection(l10n.privacyMoodleTitle, l10n.privacyMoodleBody),
        _LegalSection(l10n.privacyNextcloudTitle, l10n.privacyNextcloudBody),
        _LegalSection(l10n.privacyRequestsTitle, l10n.privacyRequestsBody),
        _LegalSection(
          l10n.privacyNotificationsTitle,
          l10n.privacyNotificationsBody,
        ),
        _LegalSection(
          l10n.privacyExternalServicesTitle,
          l10n.privacyExternalServicesBody,
        ),
        _LegalSection(l10n.privacyProvisionTitle, l10n.privacyProvisionBody),
        _LegalSection(l10n.privacyRightsTitle, l10n.privacyRightsBody),
        _LegalSection(l10n.privacyChangesTitle, l10n.privacyChangesBody),
        _LegalSection(
          l10n.aboutIndependenceTitle,
          l10n.aboutIndependenceNotice,
        ),
      ],
    };

    return ScreenScaffold(
      eyebrow: ModuleCategory.app.label(l10n),
      title: title,
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: context.metrics.screenPadding,
        ),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Text(
            page == LegalPage.privacy
                ? l10n.privacyLastUpdated
                : l10n.legalLastUpdated,
            style: text.bodySmall,
          ),
          for (final _LegalSection section in sections) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            Semantics(
              header: true,
              child: Text(section.title, style: text.titleMedium),
            ),
            const SizedBox(height: AppSpacing.sm),
            LinkifiedText(section.body, style: text.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}
