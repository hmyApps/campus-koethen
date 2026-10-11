// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The two submission types, their limits, and what survives a version change.
library;

import 'package:campus_koethen/features/requests/domain/application_files.dart';
import 'package:campus_koethen/features/requests/domain/case_status.dart';
import 'package:campus_koethen/features/requests/domain/gremio_origin.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:campus_koethen/features/requests/domain/request_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_gremio.dart';

final DateTime _now = DateTime(2026, 8, 6, 12);

FinanceApplicationDraft _application({
  int? locationId = 1,
  String title = 'Grillabend am FB5',
  String applicant = 'Testperson',
  Map<ApplicationFileSlot, RequestAttachment>? files,
}) => FinanceApplicationDraft(
  id: 'draft-1',
  createdAt: _now,
  updatedAt: _now,
  idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
  locationId: locationId,
  title: title,
  applicant: applicant,
  files:
      files ??
      <ApplicationFileSlot, RequestAttachment>{
        ApplicationFileSlot.financeRequest: const RequestAttachment(
          fileName: 'antrag.pdf',
          path: 'a',
          sizeBytes: 100,
        ),
        ApplicationFileSlot.studentCard: const RequestAttachment(
          fileName: 'ausweis.png',
          path: 'b',
          sizeBytes: 100,
        ),
      },
);

FeedbackDraft _feedback({
  int? areaId = 1,
  String submitterName = '',
  String feedback = 'Die Öffnungszeiten sollten verlängert werden.',
}) => FeedbackDraft(
  id: 'draft-2',
  createdAt: _now,
  updatedAt: _now,
  idempotencyKey: '550e8400-e29b-41d4-a716-446655440001',
  areaId: areaId,
  submitterName: submitterName,
  feedback: feedback,
);

void main() {
  group('the application draft', () {
    test('holds exactly the fields the endpoint takes', () {
      final Map<String, dynamic> json = _application().toJson();

      expect(
        json.keys,
        containsAll(<String>['locationId', 'title', 'applicant']),
      );
      // Everything the placeholder version invented is gone. Keeping any of it
      // would preserve the illusion that it is going to be sent.
      for (final String obsolete in <String>[
        'category',
        'amount',
        'currency',
        'purpose',
        'description',
        'contactName',
        'contactEmail',
      ]) {
        expect(json.containsKey(obsolete), isFalse, reason: obsolete);
      }
    });

    test('accepts a complete application', () {
      expect(RequestValidation.validate(_application()).isValid, isTrue);
    });

    test('requires location, subject, applicant and both files', () {
      final RequestValidation result = RequestValidation.validate(
        _application(
          locationId: null,
          title: '  ',
          applicant: '',
          files: const <ApplicationFileSlot, RequestAttachment>{},
        ),
      );

      expect(
        result.errorFor(RequestField.location),
        RequestFieldError.locationMissing,
      );
      expect(
        result.errorFor(RequestField.title),
        RequestFieldError.titleMissing,
      );
      expect(
        result.errorFor(RequestField.applicant),
        RequestFieldError.applicantMissing,
      );
      expect(
        result.errorFor(RequestField.financeRequestFile),
        RequestFieldError.requiredFileMissing,
      );
      expect(
        result.errorFor(RequestField.studentCardFile),
        RequestFieldError.requiredFileMissing,
      );
      // The annexes are optional and must not be demanded.
      expect(result.errorFor(RequestField.annexAFile), isNull);
      expect(result.errorFor(RequestField.annexBFile), isNull);
    });

    test('caps subject and applicant at 200 characters', () {
      final String long = 'x' * 201;
      final RequestValidation result = RequestValidation.validate(
        _application(title: long, applicant: long),
      );

      expect(
        result.errorFor(RequestField.title),
        RequestFieldError.titleTooLong,
      );
      expect(
        result.errorFor(RequestField.applicant),
        RequestFieldError.applicantTooLong,
      );
      expect(
        RequestValidation.validate(
          _application(title: 'x' * 200, applicant: 'y' * 200),
        ).isValid,
        isTrue,
        reason: 'exactly 200 is still allowed',
      );
    });

    test('refuses a file of the wrong type in a slot', () {
      final RequestValidation result = RequestValidation.validate(
        _application(
          files: <ApplicationFileSlot, RequestAttachment>{
            // The finance request is PDF only — a photo does not belong here.
            ApplicationFileSlot.financeRequest: const RequestAttachment(
              fileName: 'antrag.png',
              path: 'a',
              sizeBytes: 10,
            ),
            ApplicationFileSlot.studentCard: const RequestAttachment(
              fileName: 'ausweis.pdf',
              path: 'b',
              sizeBytes: 10,
            ),
          },
        ),
      );

      expect(
        result.errorFor(RequestField.financeRequestFile),
        RequestFieldError.fileWrongType,
      );
      expect(result.errorFor(RequestField.studentCardFile), isNull);
    });

    test('refuses a file over 25 MB', () {
      const int overLimit = 25 * 1024 * 1024 + 1;
      final RequestValidation result = RequestValidation.validate(
        _application(
          files: <ApplicationFileSlot, RequestAttachment>{
            ApplicationFileSlot.financeRequest: const RequestAttachment(
              fileName: 'antrag.pdf',
              path: 'a',
              sizeBytes: overLimit,
            ),
            ApplicationFileSlot.studentCard: const RequestAttachment(
              fileName: 'ausweis.pdf',
              path: 'b',
              sizeBytes: 10,
            ),
          },
        ),
      );

      expect(
        result.errorFor(RequestField.financeRequestFile),
        RequestFieldError.fileTooLarge,
      );
    });

    test('the student card takes PDF, PNG and JPEG', () {
      const ApplicationFileSlot card = ApplicationFileSlot.studentCard;
      expect(card.accepts('a.pdf'), isTrue);
      expect(card.accepts('a.png'), isTrue);
      expect(card.accepts('a.jpg'), isTrue);
      expect(card.accepts('a.jpeg'), isTrue);
      expect(card.accepts('a.docx'), isFalse);
      expect(card.contentTypeFor('a.jpeg'), 'image/jpeg');
    });
  });

  group('the feedback draft', () {
    test('holds exactly the fields the endpoint takes', () {
      final Map<String, dynamic> json = _feedback().toJson();

      expect(json.keys, containsAll(<String>['areaId', 'feedback']));
      for (final String obsolete in <String>['title', 'category', 'files']) {
        expect(json.containsKey(obsolete), isFalse, reason: obsolete);
      }
    });

    test('leaves a blank name out of the wire payload entirely', () {
      // Not "Anonym": the committee records that itself, and putting the word
      // in the user's mouth would claim they typed it.
      expect(_feedback(submitterName: '').wireSubmitterName, isNull);
      expect(_feedback(submitterName: '   ').wireSubmitterName, isNull);
      expect(_feedback(submitterName: ' Max ').wireSubmitterName, 'Max');
    });

    test('requires an area and a text', () {
      final RequestValidation result = RequestValidation.validate(
        _feedback(areaId: null, feedback: '   '),
      );

      expect(result.errorFor(RequestField.area), RequestFieldError.areaMissing);
      expect(
        result.errorFor(RequestField.feedback),
        RequestFieldError.feedbackMissing,
      );
    });

    test('counts user-perceived characters like the text field does', () {
      // `TextField.maxLength` counts grapheme clusters. Counting UTF-16 units
      // here flagged a title the field itself had accepted as too long.
      const String emoji = '\u{1F389}';
      final String title = emoji * 200;
      expect(title.length, 400, reason: 'two UTF-16 units each');

      expect(
        RequestValidation.validate(
          _application(title: title, applicant: emoji * 200),
        ).isValid,
        isTrue,
      );
      expect(
        RequestValidation.validate(
          _feedback(submitterName: emoji * 200, feedback: emoji * 10000),
        ).isValid,
        isTrue,
      );
      expect(
        RequestValidation.validate(
          _application(title: emoji * 201),
        ).errorFor(RequestField.title),
        RequestFieldError.titleTooLong,
      );
    });

    test('caps the name at 200 and the text at 10000 characters', () {
      final RequestValidation result = RequestValidation.validate(
        _feedback(submitterName: 'x' * 201, feedback: 'y' * 10001),
      );

      expect(
        result.errorFor(RequestField.submitterName),
        RequestFieldError.submitterNameTooLong,
      );
      expect(
        result.errorFor(RequestField.feedback),
        RequestFieldError.feedbackTooLong,
      );
      expect(
        RequestValidation.validate(_feedback(feedback: 'y' * 10000)).isValid,
        isTrue,
      );
    });
  });

  group('server-side issues', () {
    test('map onto the real form fields by their wire names', () {
      expect(RequestField.fromWire('title'), RequestField.title);
      expect(RequestField.fromWire('applicant'), RequestField.applicant);
      expect(RequestField.fromWire('locationId'), RequestField.location);
      expect(RequestField.fromWire('areaId'), RequestField.area);
      expect(RequestField.fromWire('feedback'), RequestField.feedback);
      expect(
        RequestField.fromWire('finance_request'),
        RequestField.financeRequestFile,
      );
      // A field this build does not know is reported as unmapped rather than
      // silently swallowed.
      expect(RequestField.fromWire('somethingNew'), isNull);
    });
  });

  group('reading an older stored draft', () {
    test('keeps subject, applicant, location and files', () {
      final RequestDraft? restored = RequestDraft.fromJson(<String, dynamic>{
        'id': 'old-1',
        'kind': 'finance-application',
        'createdAt': '2026-07-01T10:00:00.000Z',
        'updatedAt': '2026-07-01T10:00:00.000Z',
        'idempotencyKey': '550e8400-e29b-41d4-a716-446655440000',
        'title': 'Alter Antrag',
        'applicant': 'Testperson',
        'locationId': 3,
        // Fields the placeholder version wrote and the endpoint never had.
        'category': 'event',
        'amount': '120.50',
        'purpose': 'Grillkohle',
        'description': 'Lange Beschreibung',
        'contactEmail': 'jemand@example.invalid',
        'files': <String, dynamic>{
          'finance_request': <String, dynamic>{
            'fileName': 'antrag.pdf',
            'path': 'x',
          },
        },
      });

      expect(restored, isA<FinanceApplicationDraft>());
      final FinanceApplicationDraft draft =
          restored! as FinanceApplicationDraft;
      expect(draft.title, 'Alter Antrag');
      expect(draft.applicant, 'Testperson');
      expect(draft.locationId, 3);
      expect(draft.fileFor(ApplicationFileSlot.financeRequest), isNotNull);
      // And nothing obsolete comes back out.
      expect(draft.toJson().containsKey('amount'), isFalse);
    });

    test('carries an old feedback description over as the feedback text', () {
      final RequestDraft? restored = RequestDraft.fromJson(<String, dynamic>{
        'id': 'old-2',
        'kind': 'feedback',
        'idempotencyKey': '550e8400-e29b-41d4-a716-446655440001',
        'description': 'Der alte Text',
        'category': '7',
      });

      expect(restored, isA<FeedbackDraft>());
      final FeedbackDraft draft = restored! as FeedbackDraft;
      expect(draft.feedback, 'Der alte Text');
      // The old category was an app-side label. Reading it as an areaId would
      // file the feedback with whichever board happens to hold that number.
      expect(draft.areaId, isNull);
    });

    test(
      'replaces an unusable idempotency key rather than failing to load',
      () {
        final RequestDraft? restored = RequestDraft.fromJson(<String, dynamic>{
          'id': 'old-3',
          'kind': 'feedback',
          'idempotencyKey': 'zu-kurz',
          'feedback': 'Text',
        });

        expect(restored, isNotNull);
        expect(restored!.idempotencyKey.length, greaterThanOrEqualTo(16));
      },
    );
  });

  group('the pending-submission guard', () {
    test('expires exactly 30 days after the FIRST attempt', () {
      final PendingSubmission pending = PendingSubmission(
        firstAttemptAt: DateTime(2026, 7, 1),
        fingerprint: 'x',
      );

      expect(pending.isExpiredAt(DateTime(2026, 7, 30)), isFalse);
      expect(pending.isExpiredAt(DateTime(2026, 7, 31)), isTrue);
    });

    test('the fingerprint changes when any sent value changes', () {
      final String base = _application().payloadFingerprint;

      expect(_application(title: 'Anderes').payloadFingerprint, isNot(base));
      expect(_application(locationId: 2).payloadFingerprint, isNot(base));
      expect(
        _application(applicant: 'Andere Person').payloadFingerprint,
        isNot(base),
      );
      // And not when something that is never sent changes.
      expect(
        _application().copyWith(updatedAt: DateTime(2027)).payloadFingerprint,
        base,
      );
    });

    test(
      'a blank and an "Anonym-by-omission" feedback differ by text only',
      () {
        expect(
          _feedback(submitterName: '').payloadFingerprint,
          _feedback(submitterName: '   ').payloadFingerprint,
        );
      },
    );
  });

  group('the origin allowlist', () {
    test('accepts only the configured HTTPS origin', () {
      final GremioOrigin origin = GremioOrigin.parse(kFakeBaseUrl)!;

      expect(origin.allows('$kFakeBaseUrl/status/abc'), isTrue);
      expect(origin.allows('http://gremio.example/status/abc'), isFalse);
      // A suffix match would let this through — it must not.
      expect(
        origin.allows('https://gremio.example.attacker.invalid/status/abc'),
        isFalse,
      );
      expect(origin.allows('https://other.invalid/status/abc'), isFalse);
      expect(origin.allows('https://user:pw@gremio.example/status'), isFalse);
      expect(origin.allows('https://gremio.example:8443/status'), isFalse);
      expect(origin.allows(''), isFalse);
      expect(origin.allows(null), isFalse);
    });

    test('refuses to be built from anything but HTTPS', () {
      expect(GremioOrigin.parse('http://gremio.example'), isNull);
      expect(GremioOrigin.parse(''), isNull);
      expect(GremioOrigin.parse('  '), isNull);
      expect(GremioOrigin.parse('gremio.example'), isNull);
      expect(GremioOrigin.parse('https://user:pw@gremio.example'), isNull);
    });

    test('never puts a token-bearing path in its own description', () {
      final GremioOrigin origin = GremioOrigin.parse(kFakeBaseUrl)!;
      expect(origin.toString(), isNot(contains('testtoken')));
    });
  });

  group('parsing a status response', () {
    test('reads every field of an application', () {
      final CaseStatus? status = CaseStatus.fromJson(
        applicationStatusBody(
          publicNote: 'Bitte reiche noch eine Quittung nach.',
          resubmittedAt: '2026-08-06T09:00:00.000Z',
          archived: true,
          canUpload: true,
          submitMode: 'receipt',
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

      expect(status, isA<ApplicationCaseStatus>());
      final ApplicationCaseStatus app = status! as ApplicationCaseStatus;
      expect(app.title, 'Grillabend am FB5');
      expect(app.applicant, 'Testperson');
      expect(app.statusName, 'In Bearbeitung');
      expect(app.number, 'A_0042_2026');
      expect(app.archived, isTrue);
      expect(app.resubmittedAt, isNotNull);
      expect(app.publicNote, 'Bitte reiche noch eine Quittung nach.');
      expect(app.documents, hasLength(1));
      expect(app.documents.single.kind, 'finance_request');
      expect(app.actions.canUploadDocuments, isTrue);
      expect(app.actions.submitMode, 'receipt');
    });

    test('reads every field of a feedback', () {
      final CaseStatus? status = CaseStatus.fromJson(
        feedbackStatusBody(submitterName: 'Max Mustermann'),
      );

      expect(status, isA<FeedbackCaseStatus>());
      final FeedbackCaseStatus fb = status! as FeedbackCaseStatus;
      expect(fb.area, 'Bibliothek');
      expect(fb.submitterName, 'Max Mustermann');
      expect(fb.text, 'Die Öffnungszeiten sollten verlängert werden.');
      expect(fb.documents, isEmpty);
      expect(fb.actions.canUploadDocuments, isFalse);
      expect(fb.actions.submitMode, isNull);
    });

    test('keeps a null status name as null instead of inventing one', () {
      final CaseStatus? status = CaseStatus.fromJson(
        applicationStatusBody(name: null, number: null),
      );

      expect(status!.statusName, isNull);
      expect(status.number, isNull);
    });

    test('ignores unknown extra fields', () {
      final Map<String, dynamic> body = applicationStatusBody()
        ..['somethingNewTheServerAdded'] = <String, dynamic>{'a': 1};

      expect(CaseStatus.fromJson(body), isA<ApplicationCaseStatus>());
    });

    test('refuses a body that is not one of the two documented types', () {
      expect(
        CaseStatus.fromJson(<String, dynamic>{'type': 'inventory'}),
        isNull,
      );
      expect(CaseStatus.fromJson(<String, dynamic>{}), isNull);
      expect(CaseStatus.fromJson('nope'), isNull);
      // Missing required links: unusable, so not a status at all.
      final Map<String, dynamic> broken = applicationStatusBody()
        ..remove('statusUrl');
      expect(CaseStatus.fromJson(broken), isNull);
    });

    test('leaves a missing document filename empty for the UI to name', () {
      // A hardcoded German fallback ended up as the viewer title (AGENTS §6).
      final StatusDocument? document = StatusDocument.fromJson(
        <String, dynamic>{
          'kind': 'other',
          'downloadUrl': '$kFakeStatusUrl/documents/1',
        },
      );
      expect(document, isNotNull);
      expect(document!.filename, isNull);
      expect(document.label, 'other');
    });

    test('never names a link in its own description', () {
      final CaseStatus status = CaseStatus.fromJson(applicationStatusBody())!;
      expect(status.toString(), isNot(contains('testtoken')));
    });
  });
}
