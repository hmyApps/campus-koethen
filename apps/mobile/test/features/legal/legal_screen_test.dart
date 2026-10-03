// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/features/legal/presentation/legal_screen.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

Future<AppLocalizations> _l10n(Locale locale) =>
    AppLocalizations.delegate.load(locale);

void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('German legal copy identifies the responsible entities', () async {
    final AppLocalizations l10n = await _l10n(AppLocales.german);

    expect(l10n.imprintProviderBody, contains('Erik Engler'));
    expect(l10n.imprintProviderBody, contains('Leviora Studio'));
    expect(l10n.imprintProviderBody, contains('Gartenstraße 29C'));
    expect(l10n.imprintProviderBody, contains('erik@leviora.studio'));
    expect(l10n.imprintProviderBody, contains('+49 151 10481071'));
    expect(l10n.imprintDevelopmentBody, contains('Jona Loreen Sommer'));
    expect(
      l10n.imprintDevelopmentBody,
      contains('Jona Loreen Sommer ist nicht Teil von Leviora Studio.'),
    );
    expect(
      l10n.imprintBackendBody,
      contains('Studierendenschaft der Hochschule Anhalt'),
    );
    expect(l10n.imprintBackendBody, contains('Körperschaft'));
    expect(l10n.imprintBackendBody, contains('stura@hs-anhalt.de'));
    expect(l10n.imprintEditorialBody, contains('Vorsitzender'));
    expect(l10n.imprintEditorialBody, contains('Bernburger Straße 55'));
    expect(l10n.imprintCopyrightBody, contains('Erik Engler'));
    expect(l10n.imprintCopyrightBody, contains('Jona Loreen Sommer'));
  });

  test('privacy copy covers every implemented processing path', () async {
    final AppLocalizations de = await _l10n(AppLocales.german);
    final AppLocalizations en = await _l10n(AppLocales.english);

    for (final AppLocalizations l10n in <AppLocalizations>[de, en]) {
      expect(l10n.privacyHostingBody, contains('Hostinger International Ltd.'));
      expect(l10n.privacyHostingBody, contains('hostinger.com/legal/dpa'));
      expect(l10n.privacyGradesBody, contains('service.ssc.hs-anhalt.de'));
      expect(l10n.privacyGradesBody, contains('sscportal.ssc.hs-anhalt.de'));
      expect(l10n.privacyMoodleBody, contains('moodle.hs-anhalt.de'));
      expect(l10n.privacyRequestsBody, contains('antrag.sturahsa.de'));
      expect(l10n.privacyRightsBody, contains('stura@hs-anhalt.de'));
    }

    expect(de.privacyHostingBody, contains('Deutschland'));
    expect(en.privacyHostingBody, contains('Germany'));
    expect(de.privacyHostingBody, contains('2021/914'));
    expect(en.privacyHostingBody, contains('2021/914'));
    expect(de.privacyScopeBody, contains('Gartenstraße 29C'));
    expect(en.privacyScopeBody, contains('Gartenstraße 29C'));
    expect(de.privacyBackendStorageBody, contains('max-file=1'));
    expect(de.privacyBackendStorageBody, contains('max-size=4m'));
    expect(de.privacyBackendStorageBody, contains('etwa 5 MB'));
    expect(en.privacyBackendStorageBody, contains('max-file=1'));
    expect(en.privacyBackendStorageBody, contains('max-size=4m'));
    expect(en.privacyBackendStorageBody, contains('about 5 MB'));
    expect(de.privacyLocalBody, contains('Art. 6 Abs. 1 Buchst. b DSGVO'));
    expect(de.privacyLocalBody, contains('Sitzungscookies'));
    expect(en.privacyLocalBody, contains('Article 6(1)(b) GDPR'));
    expect(en.privacyLocalBody, contains('session cookies'));
    expect(de.privacyExternalServicesBody, contains('keine Analyse-'));
    expect(en.privacyExternalServicesBody, contains('no analytics'));
  });

  testWidgets('imprint remains reachable with large text', (
    WidgetTester tester,
  ) async {
    _smallPhone(tester);
    await pumpScreen(
      tester,
      const LegalScreen(page: LegalPage.imprint),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Urheberrecht'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Urheberrecht'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
