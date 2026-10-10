// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// What the two forms and the detail view actually put on screen.
library;

import 'dart:async';

import 'package:campus_koethen/core/links/safe_link_launcher.dart';
import 'package:campus_koethen/core/locale/locale_mode.dart';
import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/core/theme/app_icons.dart';
import 'package:campus_koethen/features/requests/application/requests_controller.dart';
import 'package:campus_koethen/features/requests/application/requests_providers.dart';
import 'package:campus_koethen/features/requests/data/attachment_picker.dart';
import 'package:campus_koethen/features/requests/domain/application_files.dart';
import 'package:campus_koethen/features/requests/domain/application_location.dart';
import 'package:campus_koethen/features/requests/domain/case_status.dart';
import 'package:campus_koethen/features/requests/domain/feedback_area.dart';
import 'package:campus_koethen/features/requests/domain/gremio_origin.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:campus_koethen/features/requests/domain/request_gateway.dart';
import 'package:campus_koethen/features/requests/domain/request_validation.dart';
import 'package:campus_koethen/features/requests/domain/status_gateway.dart';
import 'package:campus_koethen/features/requests/domain/submitted_case.dart';
import 'package:campus_koethen/features/requests/presentation/application_form_screen.dart';
import 'package:campus_koethen/features/requests/presentation/feedback_form_screen.dart';
import 'package:campus_koethen/features/requests/presentation/request_form_parts.dart';
import 'package:campus_koethen/features/requests/presentation/requests_screen.dart';
import 'package:campus_koethen/features/requests/presentation/submission_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_gremio.dart';
import '../../support/pump_app.dart';

final DateTime _now = DateTime(2026, 8, 6, 12);

const List<ApplicationLocation> _locations = <ApplicationLocation>[
  ApplicationLocation(id: 1, name: 'Standort A'),
  ApplicationLocation(id: 4, name: 'Zentrale'),
];

const List<FeedbackArea> _areas = <FeedbackArea>[
  FeedbackArea(id: 1, name: 'Bibliothek'),
  FeedbackArea(id: 2, name: 'Mensa'),
];

class _RecordingLinkLauncher implements SafeLinkLauncher {
  _RecordingLinkLauncher({this.result = LinkLaunchResult.opened});

  final LinkLaunchResult result;
  final List<String> opened = <String>[];

  @override
  Future<LinkLaunchResult> open(String? rawUrl) async {
    if (rawUrl != null) opened.add(rawUrl);
    return result;
  }
}

List<Override> _overrides({
  FlakyRequestStore? store,
  ScriptedRequestGateway? gateway,
  ScriptedStatusGateway? status,
  AsyncValue<List<ApplicationLocation>>? locations,
  AsyncValue<List<FeedbackArea>>? areas,
  SafeLinkLauncher? linkLauncher,
}) => <Override>[
  requestStoreProvider.overrideWithValue(store ?? FlakyRequestStore()),
  requestGatewayProvider.overrideWithValue(
    gateway ?? ScriptedRequestGateway(const SubmissionNotConnected()),
  ),
  statusGatewayProvider.overrideWithValue(
    status ?? ScriptedStatusGateway(const StatusUnavailable('n/a')),
  ),
  attachmentStoreProvider.overrideWithValue(FakeAttachmentStore()),
  requestsEndpointConfiguredProvider.overrideWithValue(true),
  requestsOriginProvider.overrideWithValue(GremioOrigin.parse(kFakeBaseUrl)),
  if (linkLauncher != null)
    linkLauncherProvider.overrideWithValue(linkLauncher),
  applicationLocationsProvider.overrideWith(
    (Ref ref) async => switch (locations) {
      AsyncData<List<ApplicationLocation>>(
        :final List<ApplicationLocation> value,
      ) =>
        value,
      AsyncError<List<ApplicationLocation>>(:final Object error) => throw error,
      _ => _locations,
    },
  ),
  feedbackAreasProvider.overrideWith(
    (Ref ref) async => switch (areas) {
      AsyncData<List<FeedbackArea>>(:final List<FeedbackArea> value) => value,
      AsyncError<List<FeedbackArea>>(:final Object error) => throw error,
      _ => _areas,
    },
  ),
];

/// The order in which labels appear down the **form**.
///
/// Scoped to the scrolling body on purpose: the screen's masthead names the
/// form itself, and one of the fields happens to carry the same word. Matching
/// anywhere on the screen would compare a heading with a field label.
List<String> _labelOrder(WidgetTester tester, List<String> candidates) {
  final List<(double, String)> found = <(double, String)>[];
  for (final String label in candidates) {
    final Finder finder = find.descendant(
      of: find.byType(ListView),
      matching: find.text(label),
    );
    if (finder.evaluate().isEmpty) continue;
    found.add((tester.getTopLeft(finder.first).dy, label));
  }
  found.sort(((double, String) a, (double, String) b) => a.$1.compareTo(b.$1));
  return found.map(((double, String) e) => e.$2).toList(growable: false);
}

void main() {
  group('the finance application form', () {
    testWidgets('asks for the fields in the documented order', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(
        _labelOrder(tester, <String>[
          'Standort',
          'Antragsgegenstand',
          'Antragstellende Person',
          'Finanzantrag',
          'Studierendenausweis',
          'Anlage A',
          'Anlage B',
        ]),
        <String>[
          'Standort',
          'Antragsgegenstand',
          'Antragstellende Person',
          'Finanzantrag',
          'Studierendenausweis',
          'Anlage A',
          'Anlage B',
        ],
      );
    });

    testWidgets('shows none of the invented placeholder fields', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      for (final String gone in <String>[
        'Betrag',
        'Verwendungszweck',
        'Kategorie',
        'Beschreibung',
        'E-Mail',
      ]) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('enforces the 200-character limit in the field itself', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      final Iterable<TextField> fields = tester.widgetList<TextField>(
        find.byType(TextField),
      );
      expect(fields, hasLength(2));
      for (final TextField field in fields) {
        expect(field.maxLength, 200);
      }
    });

    testWidgets('says the card is processed internally only', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('nur intern verarbeitet'), findsOneWidget);
    });

    testWidgets('offers a retry when the locations cannot be loaded', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(
          locations: AsyncError<List<ApplicationLocation>>(
            Exception('offline'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Die Standorte konnten nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Erneut laden'), findsOneWidget);
    });

    testWidgets('says so when no location is available at all', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(
          locations: const AsyncData<List<ApplicationLocation>>(
            <ApplicationLocation>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Zurzeit steht kein Standort zur Auswahl.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed submission keeps everything the user typed', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore();
      await pumpScreen(
        tester,
        const ApplicationFormScreen(),
        overrides: _overrides(
          store: store,
          gateway: ScriptedRequestGateway(
            const SubmissionRateLimited(retryAfter: Duration(seconds: 30)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Grillabend');
      await tester.enterText(find.byType(TextField).last, 'Testperson');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Antrag einreichen'));
      await tester.pumpAndSettle();

      // Still on screen, still filled in.
      expect(find.text('Grillabend'), findsOneWidget);
      expect(find.text('Testperson'), findsOneWidget);
      expect(
        (store.drafts.single as FinanceApplicationDraft).title,
        'Grillabend',
      );
    });
  });

  group('the feedback form', () {
    testWidgets('asks for area, optional name and text, in that order', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const FeedbackFormScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(
        _labelOrder(tester, <String>[
          'Bereich',
          'Dein Name (optional)',
          'Dein Feedback',
        ]),
        <String>['Bereich', 'Dein Name (optional)', 'Dein Feedback'],
      );
      expect(
        find.textContaining('erscheint dein Feedback als'),
        findsOneWidget,
      );
      expect(find.text('Bis zu 10.000 Zeichen.'), findsOneWidget);
    });

    testWidgets('caps the name at 200 and the text at 10000', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const FeedbackFormScreen(),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      final List<TextField> fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.maxLength, 200);
      expect(fields.last.maxLength, 10000);
      expect(fields.last.minLines, 7);
    });

    testWidgets('offers a retry when the areas cannot be loaded', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const FeedbackFormScreen(),
        overrides: _overrides(
          areas: AsyncError<List<FeedbackArea>>(
            Exception('offline'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Die Bereiche konnten nicht geladen werden.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'an unclear outcome freezes the form, not just the stored draft',
      (WidgetTester tester) async {
        // REQ-1. The controller froze the draft correctly; the screen kept its
        // own un-frozen copy. So the fields stayed editable while `save()`
        // silently refused every keystroke, and pressing send again replayed
        // the LOCAL copy — skipping the fingerprint and 30-day checks and
        // landing in the 409 conflict the freeze exists to prevent.
        final ScriptedRequestGateway gateway = ScriptedRequestGateway(
          const SubmissionOutcomeUnknown('transport'),
        );
        await pumpScreen(
          tester,
          const FeedbackFormScreen(),
          overrides: _overrides(gateway: gateway),
        );
        await tester.pumpAndSettle();

        // A complete draft, or validation stops before the gateway is asked.
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bibliothek').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'Mein Hinweis');
        await tester.pumpAndSettle();

        final Finder send = find.widgetWithText(
          FilledButton,
          'Feedback absenden',
        );
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();

        expect(gateway.keysUsed, hasLength(1));

        // The frozen banner is on screen…
        expect(find.text('Ausgang unklar'), findsOneWidget);
        // …and the fields it describes really are disabled.
        final Iterable<TextField> fields = tester.widgetList<TextField>(
          find.byType(TextField),
        );
        expect(fields.every((TextField f) => f.enabled == false), isTrue);
      },
    );

    testWidgets('a rejected submission keeps the text', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const FeedbackFormScreen(),
        overrides: _overrides(
          gateway: ScriptedRequestGateway(
            const SubmissionOutcomeUnknown('transport'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Mein Hinweis');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feedback absenden'));
      await tester.pumpAndSettle();

      expect(find.text('Mein Hinweis'), findsOneWidget);
    });

    testWidgets('external rejection text never bypasses localization', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const FeedbackFormScreen(),
        locale: AppLocales.english,
        overrides: _overrides(
          gateway: ScriptedRequestGateway(
            const SubmissionRejected(
              message: 'Bitte Feedback prüfen.',
              fieldErrors: <RequestField, String>{
                RequestField.feedback: 'Ungültige Eingabe.',
              },
              generalIssues: <String>['Unbekanntes Feld.'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bibliothek').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'My feedback');
      await tester.tap(find.text('Send feedback'));
      await tester.pumpAndSettle();

      expect(find.text('The information was not accepted.'), findsOneWidget);
      expect(
        find.text('Please check your information and try again.'),
        findsOneWidget,
      );
      expect(find.text('Please check this entry.'), findsOneWidget);
      expect(find.textContaining('Bitte'), findsNothing);
      expect(find.textContaining('Ungültige'), findsNothing);
      expect(find.textContaining('Unbekanntes'), findsNothing);
    });
  });

  group('a submission in flight (E-01, VE-N02)', () {
    FinanceApplicationDraft completeApplication() => FinanceApplicationDraft(
      id: 'draft-app',
      createdAt: _now,
      updatedAt: _now,
      idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
      locationId: 1,
      title: 'Grillabend',
      applicant: 'Testperson',
      files: const <ApplicationFileSlot, RequestAttachment>{
        ApplicationFileSlot.financeRequest: RequestAttachment(
          fileName: 'antrag.pdf',
          path: 'fake-antrag',
          sizeBytes: 3,
        ),
        ApplicationFileSlot.studentCard: RequestAttachment(
          fileName: 'ausweis.pdf',
          path: 'fake-ausweis',
          sizeBytes: 3,
        ),
      },
    );

    testWidgets('locks every field and file slot while uploading', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..drafts = <RequestDraft>[completeApplication()];
      final ScriptedRequestGateway gateway = ScriptedRequestGateway(
        const SubmissionOutcomeUnknown('transport'),
      )..gate = Completer<void>();
      await pumpScreen(
        tester,
        const ApplicationFormScreen(draftId: 'draft-app'),
        overrides: _overrides(store: store, gateway: gateway),
      );
      await tester.pumpAndSettle();

      final Finder send = find.text('Antrag einreichen');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verbindlich absenden'));
      // Not pumpAndSettle: the upload spinner never settles.
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(gateway.keysUsed, hasLength(1));

      // Replacing or removing a file now would delete the bytes on the wire.
      expect(
        tester
            .widgetList<FileSlotField>(find.byType(FileSlotField))
            .every((FileSlotField slot) => !slot.enabled),
        isTrue,
      );
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((TextField field) => field.enabled == false),
        isTrue,
      );

      gateway.gate!.complete();
      await tester.pumpAndSettle();
      // An unclear outcome keeps it locked — as a frozen draft now.
      expect(find.text('Ausgang unklar'), findsWidgets);
    });

    testWidgets('locks the feedback form while uploading', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..drafts = <RequestDraft>[
          FeedbackDraft(
            id: 'draft-fb',
            createdAt: _now,
            updatedAt: _now,
            idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
            areaId: 1,
            feedback: 'Mein Hinweis',
          ),
        ];
      final ScriptedRequestGateway gateway = ScriptedRequestGateway(
        const SubmissionRateLimited(),
      )..gate = Completer<void>();
      await pumpScreen(
        tester,
        const FeedbackFormScreen(draftId: 'draft-fb'),
        overrides: _overrides(store: store, gateway: gateway),
      );
      await tester.pumpAndSettle();

      final Finder send = find.text('Feedback absenden');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((TextField field) => field.enabled == false),
        isTrue,
      );

      // A plain rejection unlocks it again — and the spinner is gone.
      gateway.gate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((TextField field) => field.enabled != false),
        isTrue,
      );
      expect(find.text('Wird übermittelt …'), findsNothing);
    });

    testWidgets('the list marks a running upload and keeps it', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..drafts = <RequestDraft>[completeApplication()];
      final ProviderContainer container = await pumpScreen(
        tester,
        const RequestsScreen(),
        overrides: _overrides(store: store),
      );
      await tester.pumpAndSettle();

      // The form was left while its upload kept running.
      container.read(requestsInFlightProvider.notifier).start('draft-app');
      await tester.pumpAndSettle();

      expect(find.text('Wird übermittelt …'), findsOneWidget);
      final IconButton delete = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, AppIcons.delete_outline),
      );
      expect(delete.onPressed, isNull);
    });
  });

  group('the main screen', () {
    testWidgets('offers both actions and both lists', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const RequestsScreen(), overrides: _overrides());
      await tester.pumpAndSettle();

      expect(find.text('Finanzantrag stellen'), findsOneWidget);
      expect(find.text('Feedback geben'), findsOneWidget);
      expect(find.text('Meine Einreichungen'), findsOneWidget);
      expect(find.text('Entwürfe'), findsOneWidget);
      expect(find.text('Noch nichts eingereicht.'), findsOneWidget);
    });

    testWidgets('uses the requested action icons and theme brand colour', (
      WidgetTester tester,
    ) async {
      for (final (ThemeMode mode, Color expected) in <(ThemeMode, Color)>[
        (ThemeMode.light, AppColors.light.primary),
        (ThemeMode.dark, AppColors.dark.primary),
      ]) {
        await pumpScreen(
          tester,
          const RequestsScreen(),
          themeMode: mode,
          overrides: _overrides(),
        );
        await tester.pumpAndSettle();

        for (final IconData iconData in <IconData>[
          AppIcons.file_euro,
          AppIcons.message_2,
        ]) {
          final Icon icon = tester.widget<Icon>(find.byIcon(iconData));
          expect(icon.color, expected);
        }
      }
    });

    testWidgets('can be pulled to refresh', (WidgetTester tester) async {
      await pumpScreen(tester, const RequestsScreen(), overrides: _overrides());
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('lists a submitted case with its number and status', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[
          SubmittedCase(
            id: 'case-1',
            kind: RequestKind.financeApplication,
            submittedAt: _now,
            statusUrl: kFakeStatusUrl,
            receiptPdfUrl: kFakeReceiptUrl,
            number: 'A_0042_2026',
            localTitle: 'Grillabend am FB5',
          ),
        ];

      await pumpScreen(
        tester,
        const RequestsScreen(),
        overrides: _overrides(
          store: store,
          status: ScriptedStatusGateway(
            StatusLoaded(CaseStatus.fromJson(applicationStatusBody())!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grillabend am FB5'), findsOneWidget);
      expect(find.textContaining('A_0042_2026'), findsOneWidget);
      expect(find.textContaining('In Bearbeitung'), findsOneWidget);
    });
  });

  group('the detail view', () {
    Future<void> pumpDetail(
      WidgetTester tester, {
      required Map<String, dynamic> body,
      RequestKind kind = RequestKind.financeApplication,
      Locale locale = AppLocales.german,
      SafeLinkLauncher? linkLauncher,
    }) async {
      tester.view.physicalSize = const Size(430, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[
          SubmittedCase(
            id: 'case-1',
            kind: kind,
            submittedAt: _now,
            statusUrl: kFakeStatusUrl,
            receiptPdfUrl: kFakeReceiptUrl,
            number: 'A_0042_2026',
            localTitle: 'Grillabend am FB5',
          ),
        ];

      await pumpScreen(
        tester,
        const SubmissionDetailScreen(submissionId: 'case-1'),
        locale: locale,
        overrides: _overrides(
          store: store,
          status: ScriptedStatusGateway(
            StatusLoaded(CaseStatus.fromJson(body)!),
          ),
          linkLauncher: linkLauncher,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows every field of an application status', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        body: applicationStatusBody(
          publicNote: 'Bitte reiche noch eine Quittung nach.',
          archived: true,
          resubmittedAt: '2026-08-06T09:00:00.000Z',
          submitMode: 'receipt',
          canUpload: true,
          documents: <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'finance_request',
              'label': 'Finanzantrag',
              'filename': 'Finanzantrag.pdf',
              'mimeType': 'application/pdf',
              'downloadUrl': '$kFakeBaseUrl/api/status/testtoken/attachment/12',
            },
          ],
        ),
      );

      expect(find.text('Grillabend am FB5'), findsOneWidget);
      expect(find.textContaining('A_0042_2026'), findsOneWidget);
      expect(find.text('In Bearbeitung'), findsOneWidget);
      expect(find.text('Abgeschlossen'), findsWidgets);
      expect(find.text('Testperson'), findsOneWidget);
      expect(find.textContaining('Eingereicht:'), findsOneWidget);
      expect(find.textContaining('Zuletzt geändert:'), findsOneWidget);
      expect(find.textContaining('Nachgereicht:'), findsOneWidget);
      expect(find.text('Hinweis des Gremiums'), findsOneWidget);
      expect(
        find.text('Finanzantrag'),
        findsNWidgets(2),
        reason: 'the screen title and the document share the word',
      );
      expect(find.text('Eingangsbestätigung (PDF)'), findsOneWidget);
      expect(find.text('Quittung kann eingereicht werden'), findsOneWidget);
      // The boundary is stated rather than faked.
      expect(find.textContaining('Weboberfläche'), findsOneWidget);
    });

    testWidgets('shows the full feedback text', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        kind: RequestKind.feedback,
        body: feedbackStatusBody(
          text: 'Ein sehr langer Hinweis, der vollständig sichtbar sein muss.',
          submitterName: 'Max Mustermann',
        ),
      );

      expect(find.text('Bibliothek'), findsOneWidget);
      expect(find.text('Max Mustermann'), findsOneWidget);
      expect(
        find.text(
          'Ein sehr langer Hinweis, der vollständig sichtbar sein muss.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('offers the browser link for applications and feedback', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, body: applicationStatusBody());
      expect(find.text('Zum Antrag'), findsOneWidget);

      await pumpDetail(
        tester,
        kind: RequestKind.feedback,
        body: feedbackStatusBody(),
      );
      expect(find.text('Zum Antrag'), findsOneWidget);
    });

    testWidgets('opens the canonical case link through the safe launcher', (
      WidgetTester tester,
    ) async {
      final _RecordingLinkLauncher launcher = _RecordingLinkLauncher();
      await pumpDetail(
        tester,
        body: applicationStatusBody(),
        linkLauncher: launcher,
      );

      await tester.tap(find.text('Zum Antrag'));
      await tester.pumpAndSettle();

      expect(launcher.opened, <String>[kFakeStatusUrl]);
    });

    testWidgets('never hands a foreign case link to the browser', (
      WidgetTester tester,
    ) async {
      final _RecordingLinkLauncher launcher = _RecordingLinkLauncher();
      final Map<String, dynamic> body = applicationStatusBody()
        ..['statusUrl'] = 'https://attacker.example/status/testtoken';
      await pumpDetail(tester, body: body, linkLauncher: launcher);

      await tester.tap(find.text('Zum Antrag'));
      await tester.pumpAndSettle();

      expect(launcher.opened, isEmpty);
      expect(
        find.textContaining('passt nicht zu dieser Empfangsstelle'),
        findsOneWidget,
      );
    });

    testWidgets('reports when the browser cannot open the case link', (
      WidgetTester tester,
    ) async {
      final _RecordingLinkLauncher launcher = _RecordingLinkLauncher(
        result: LinkLaunchResult.failed,
      );
      await pumpDetail(
        tester,
        body: applicationStatusBody(),
        linkLauncher: launcher,
      );

      await tester.tap(find.text('Zum Antrag'));
      await tester.pumpAndSettle();

      expect(
        find.text('Der Vorgang konnte nicht im Browser geöffnet werden.'),
        findsOneWidget,
      );
    });

    testWidgets('never shows the student card or the secret link', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, body: applicationStatusBody());

      expect(find.textContaining('Studierendenausweis'), findsNothing);
      expect(find.textContaining('testtoken'), findsNothing);
      expect(find.textContaining(kFakeStatusUrl), findsNothing);
      // It says the link exists and stays put, without printing it.
      expect(find.textContaining('einzige Zugang'), findsOneWidget);
    });

    testWidgets('says "Status nicht angegeben" for a null column name', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, body: applicationStatusBody(name: null));

      expect(find.text('Status nicht angegeben'), findsOneWidget);
    });

    testWidgets('states plainly when no resubmission is offered', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, body: applicationStatusBody());

      expect(
        find.text('Zurzeit ist keine Nachreichung vorgesehen.'),
        findsOneWidget,
      );
    });

    testWidgets('renders in English too', (WidgetTester tester) async {
      await pumpDetail(
        tester,
        body: applicationStatusBody(),
        locale: AppLocales.english,
      );

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Confirmation of receipt (PDF)'), findsOneWidget);
      expect(find.text('Available actions'), findsOneWidget);
      expect(find.text('Open submission'), findsOneWidget);
    });

    testWidgets('survives a small screen with doubled text', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[
          SubmittedCase(
            id: 'case-1',
            kind: RequestKind.financeApplication,
            submittedAt: _now,
            statusUrl: kFakeStatusUrl,
            receiptPdfUrl: kFakeReceiptUrl,
            localTitle: 'Ein langer Antragsgegenstand für den Umbruchtest',
          ),
        ];

      await pumpScreen(
        tester,
        const SubmissionDetailScreen(submissionId: 'case-1'),
        textScaler: const TextScaler.linear(2),
        overrides: _overrides(
          store: store,
          status: ScriptedStatusGateway(
            StatusLoaded(CaseStatus.fromJson(applicationStatusBody())!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('detail layout matrix keeps refresh and status reachable', (
      WidgetTester tester,
    ) async {
      for (final (Size size, TextScaler scaler) in <(Size, TextScaler)>[
        (const Size(320, 900), TextScaler.noScaling),
        (const Size(360, 900), const TextScaler.linear(1.3)),
        (const Size(800, 360), TextScaler.noScaling),
        (const Size(320, 1400), const TextScaler.linear(2)),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final FlakyRequestStore store = FlakyRequestStore()
          ..cases = <SubmittedCase>[
            SubmittedCase(
              id: 'case-1',
              kind: RequestKind.financeApplication,
              submittedAt: _now,
              statusUrl: kFakeStatusUrl,
              receiptPdfUrl: kFakeReceiptUrl,
              localTitle: 'Testantrag',
            ),
          ];

        await pumpScreen(
          tester,
          const SubmissionDetailScreen(submissionId: 'case-1'),
          textScaler: scaler,
          overrides: _overrides(
            store: store,
            status: ScriptedStatusGateway(
              StatusLoaded(CaseStatus.fromJson(applicationStatusBody())!),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('Aktualisieren'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size at $scaler');
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('offers a retry when the status cannot be read', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[
          SubmittedCase(
            id: 'case-1',
            kind: RequestKind.feedback,
            submittedAt: _now,
            statusUrl: kFakeStatusUrl,
            receiptPdfUrl: kFakeReceiptUrl,
          ),
        ];

      await pumpScreen(
        tester,
        const SubmissionDetailScreen(submissionId: 'case-1'),
        overrides: _overrides(
          store: store,
          status: ScriptedStatusGateway(const StatusUnavailable('transport')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Der Status konnte nicht geladen werden.'),
        findsOneWidget,
      );
      expect(find.text('Erneut laden'), findsOneWidget);
    });

    testWidgets('a 404 does not remove the local record', (
      WidgetTester tester,
    ) async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[
          SubmittedCase(
            id: 'case-1',
            kind: RequestKind.feedback,
            submittedAt: _now,
            statusUrl: kFakeStatusUrl,
            receiptPdfUrl: kFakeReceiptUrl,
          ),
        ];

      await pumpScreen(
        tester,
        const SubmissionDetailScreen(submissionId: 'case-1'),
        overrides: _overrides(
          store: store,
          status: ScriptedStatusGateway(const StatusNotFound()),
        ),
      );
      await tester.pumpAndSettle();

      expect(store.cases, hasLength(1));
      expect(
        find.textContaining('bleibt auf dem Gerät erhalten'),
        findsOneWidget,
      );
    });
  });
}
