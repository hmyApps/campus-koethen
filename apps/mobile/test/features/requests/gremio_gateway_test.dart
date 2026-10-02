// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// What actually goes on the wire, and what every documented answer means.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_koethen/features/requests/data/gremio_request_gateway.dart';
import 'package:campus_koethen/features/requests/domain/application_files.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:campus_koethen/features/requests/domain/request_gateway.dart';
import 'package:campus_koethen/features/requests/domain/request_validation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_gremio.dart';

const String _key = '550e8400-e29b-41d4-a716-446655440000';
final DateTime _now = DateTime(2026, 8, 6, 12);

Future<(GremioRequestGateway, FakeGremioAdapter, FakeAttachmentStore)> _build(
  FakeGremioResponse Function(RequestOptions) handler,
) async {
  final FakeGremioAdapter adapter = FakeGremioAdapter(handler);
  final FakeAttachmentStore store = FakeAttachmentStore();
  return (
    GremioRequestGateway(
      dio: fakeGremioDio(adapter),
      baseUrl: kFakeBaseUrl,
      attachments: store,
    ),
    adapter,
    store,
  );
}

Future<FinanceApplicationDraft> _application(FakeAttachmentStore store) async {
  final RequestAttachment antrag = (await store.put(
    'antrag.pdf',
    Uint8List.fromList(<int>[1, 2, 3]),
  ))!;
  final RequestAttachment ausweis = (await store.put(
    'ausweis.png',
    Uint8List.fromList(<int>[4, 5, 6]),
  ))!;
  return FinanceApplicationDraft(
    id: 'draft-1',
    createdAt: _now,
    updatedAt: _now,
    idempotencyKey: _key,
    locationId: 7,
    title: 'Grillabend am FB5',
    applicant: 'Testperson',
    files: <ApplicationFileSlot, RequestAttachment>{
      ApplicationFileSlot.financeRequest: antrag,
      ApplicationFileSlot.studentCard: ausweis,
    },
  );
}

FeedbackDraft _feedback({String submitterName = ''}) => FeedbackDraft(
  id: 'draft-2',
  createdAt: _now,
  updatedAt: _now,
  idempotencyKey: _key,
  areaId: 3,
  submitterName: submitterName,
  feedback: '  Die Öffnungszeiten sollten verlängert werden.  ',
);

const FakeGremioResponse _created = FakeGremioResponse(<String, dynamic>{
  'statusUrl': kFakeStatusUrl,
  'receiptPdfUrl': kFakeReceiptUrl,
  'number': 'A_0042_2026',
}, statusCode: 201);

void main() {
  group('submitting an application', () {
    test('posts multipart to the documented path with the key', () async {
      final (gateway, adapter, store) = await _build((_) => _created);

      final SubmissionResult result = await gateway.submitApplication(
        await _application(store),
      );

      expect(result, isA<SubmissionAccepted>());
      expect(adapter.lastRequest.path, contains('/api/public/v1/applications'));
      expect(adapter.lastRequest.method, 'POST');
      expect(adapter.lastRequest.followRedirects, isFalse);
      expect(
        adapter.lastRequest.headers['Idempotency-Key'],
        _key,
        reason: 'the key is mandatory and belongs to the draft',
      );
      expect(adapter.lastRequest.contentType, contains('multipart/form-data'));
      expect(
        store.wholeFileReads,
        0,
        reason: 'multipart must consume the bounded attachment stream',
      );
    });

    test('sends exactly the documented fields, and nothing else', () async {
      final (gateway, adapter, store) = await _build((_) => _created);

      await gateway.submitApplication(await _application(store));
      final String body = adapter.bodies.last;

      for (final String field in <String>[
        'locationId',
        'title',
        'applicant',
        'finance_request',
        'student_card',
      ]) {
        expect(body, contains('name="$field"'), reason: field);
      }
      for (final String never in <String>[
        'category',
        'amount',
        'purpose',
        'description',
        'contactName',
        'contactEmail',
        'ts',
        'sig',
        'website',
      ]) {
        expect(body, isNot(contains('name="$never"')), reason: never);
      }
      // Optional annexes are absent when nothing was picked.
      expect(body, isNot(contains('name="annex_a"')));
      expect(body, isNot(contains('name="annex_b"')));
    });

    test('sends the annexes when they are there', () async {
      final (gateway, adapter, store) = await _build((_) => _created);
      final FinanceApplicationDraft base = await _application(store);
      final RequestAttachment annex = (await store.put(
        'anlage.pdf',
        Uint8List.fromList(<int>[7]),
      ))!;

      await gateway.submitApplication(
        base.withFile(ApplicationFileSlot.annexA, annex),
      );

      expect(adapter.bodies.last, contains('name="annex_a"'));
    });

    test('refuses to send an incomplete draft at all', () async {
      final (gateway, adapter, store) = await _build((_) => _created);
      final FinanceApplicationDraft draft = (await _application(
        store,
      )).copyWith(title: '');

      final SubmissionResult result = await gateway.submitApplication(draft);

      expect(result, isA<SubmissionRejected>());
      expect(
        adapter.requests,
        isEmpty,
        reason: 'no rate-limit slot is burned for an answer we already know',
      );
    });

    test('reports a missing attachment at its own field', () async {
      final (gateway, _, store) = await _build((_) => _created);
      final FinanceApplicationDraft draft = await _application(store);
      // The draft outlived its bytes — cleared storage, a restored backup.
      store.entries.clear();

      final SubmissionResult result = await gateway.submitApplication(draft);

      expect(result, isA<SubmissionRejected>());
      expect(
        (result as SubmissionRejected).fieldErrors.keys,
        contains(RequestField.financeRequestFile),
      );
    });

    test(
      'still submits a migrated draft whose old reference has no size',
      () async {
        final (gateway, adapter, store) = await _build((_) => _created);
        final FinanceApplicationDraft base = await _application(store);
        final RequestAttachment current = base.fileFor(
          ApplicationFileSlot.financeRequest,
        )!;
        final FinanceApplicationDraft migrated = base.withFile(
          ApplicationFileSlot.financeRequest,
          RequestAttachment(fileName: current.fileName, path: current.path),
        );

        final SubmissionResult result = await gateway.submitApplication(
          migrated,
        );

        expect(result, isA<SubmissionAccepted>());
        expect(adapter.requests, hasLength(1));
      },
    );
  });

  group('submitting feedback', () {
    test('posts JSON to the documented path with the key', () async {
      final (gateway, adapter, _) = await _build(
        (_) => const FakeGremioResponse(<String, dynamic>{
          'statusUrl': kFakeFeedbackStatusUrl,
          'receiptPdfUrl': kFakeFeedbackReceiptUrl,
          'number': 'F_0042_2026',
        }, statusCode: 201),
      );

      final SubmissionResult result = await gateway.submitFeedback(_feedback());

      expect(result, isA<SubmissionAccepted>());
      expect(adapter.lastRequest.path, contains('/api/public/v1/feedback'));
      expect(adapter.lastRequest.headers['Idempotency-Key'], _key);
      expect(adapter.lastRequest.contentType, contains('application/json'));
    });

    test('omits submitterName entirely when the user gave none', () async {
      final (gateway, adapter, _) = await _build(
        (_) => const FakeGremioResponse(<String, dynamic>{
          'statusUrl': kFakeFeedbackStatusUrl,
          'receiptPdfUrl': kFakeFeedbackReceiptUrl,
          'number': null,
        }, statusCode: 201),
      );

      await gateway.submitFeedback(_feedback());
      final Map<String, dynamic> sent =
          jsonDecode(adapter.bodies.last) as Map<String, dynamic>;

      expect(sent.containsKey('submitterName'), isFalse);
      expect(sent['areaId'], 3);
      // Trimmed, as the contract says.
      expect(sent['feedback'], 'Die Öffnungszeiten sollten verlängert werden.');
      expect(sent.keys.length, 2, reason: 'no invented fields');
    });

    test('sends a given name, trimmed', () async {
      final (gateway, adapter, _) = await _build(
        (_) => const FakeGremioResponse(<String, dynamic>{
          'statusUrl': kFakeFeedbackStatusUrl,
          'receiptPdfUrl': kFakeFeedbackReceiptUrl,
          'number': null,
        }, statusCode: 201),
      );

      await gateway.submitFeedback(_feedback(submitterName: '  Max  '));

      expect(
        (jsonDecode(adapter.bodies.last)
            as Map<String, dynamic>)['submitterName'],
        'Max',
      );
    });
  });

  group('the documented answers', () {
    Future<SubmissionResult> answer(FakeGremioResponse response) async {
      final (gateway, _, _) = await _build((_) => response);
      return gateway.submitFeedback(_feedback());
    }

    test('201 is a new case', () async {
      final SubmissionResult result = await answer(
        const FakeGremioResponse(<String, dynamic>{
          'statusUrl': kFakeFeedbackStatusUrl,
          'receiptPdfUrl': kFakeFeedbackReceiptUrl,
          'number': 'F_1',
        }, statusCode: 201),
      );

      expect(result, isA<SubmissionAccepted>());
      final SubmissionAccepted accepted = result as SubmissionAccepted;
      expect(accepted.wasReplay, isFalse);
      expect(accepted.number, 'F_1');
      expect(accepted.statusUrl, kFakeFeedbackStatusUrl);
    });

    test('200 with the replay header is a success, not a duplicate', () async {
      final SubmissionResult result = await answer(
        const FakeGremioResponse(
          <String, dynamic>{
            'statusUrl': kFakeFeedbackStatusUrl,
            'receiptPdfUrl': kFakeFeedbackReceiptUrl,
            'number': 'F_1',
          },
          headers: <String, String>{'Idempotency-Replayed': 'true'},
        ),
      );

      expect(result, isA<SubmissionAccepted>());
      expect((result as SubmissionAccepted).wasReplay, isTrue);
    });

    test('400 issues land on the fields they name', () async {
      final SubmissionResult result = await answer(
        const FakeGremioResponse(<String, dynamic>{
          'error': 'Bitte Feedback eingeben.',
          'issues': <Map<String, String>>[
            <String, String>{
              'field': 'feedback',
              'message': 'Bitte Feedback eingeben.',
            },
            <String, String>{
              'field': 'somethingNew',
              'message': 'Unbekanntes Feld.',
            },
          ],
        }, statusCode: 400),
      );

      expect(result, isA<SubmissionRejected>());
      final SubmissionRejected rejected = result as SubmissionRejected;
      expect(
        rejected.fieldErrors[RequestField.feedback],
        'Bitte Feedback eingeben.',
      );
      // An issue this build cannot place is kept, not swallowed.
      expect(rejected.generalIssues, contains('Unbekanntes Feld.'));
      expect(rejected.message, 'Bitte Feedback eingeben.');
    });

    test('404 means the target is gone', () async {
      expect(
        await answer(
          const FakeGremioResponse(<String, dynamic>{
            'error': 'Bereich nicht gefunden.',
          }, statusCode: 404),
        ),
        isA<SubmissionTargetGone>(),
      );
    });

    test('409 is a conflict that a retry cannot fix', () async {
      expect(
        await answer(const FakeGremioResponse(null, statusCode: 409)),
        isA<SubmissionConflict>(),
      );
    });

    test('413 is too large', () async {
      expect(
        await answer(const FakeGremioResponse(null, statusCode: 413)),
        isA<SubmissionTooLarge>(),
      );
    });

    test('415 is a client-side protocol fault of its own', () async {
      expect(
        await answer(const FakeGremioResponse(null, statusCode: 415)),
        isA<SubmissionUnsupportedMedia>(),
      );
    });

    test('429 carries Retry-After', () async {
      final SubmissionResult result = await answer(
        const FakeGremioResponse(
          <String, dynamic>{'error': 'zu viele'},
          statusCode: 429,
          headers: <String, String>{'Retry-After': '42'},
        ),
      );

      expect(result, isA<SubmissionRateLimited>());
      expect(
        (result as SubmissionRateLimited).retryAfter,
        const Duration(seconds: 42),
      );
    });

    test('a transport failure is an UNKNOWN outcome, not a failure', () async {
      // The distinction the idempotency key exists for: the case may have been
      // filed and only the answer lost.
      expect(
        await answer(const FakeGremioResponse.transportError()),
        isA<SubmissionOutcomeUnknown>(),
      );
    });

    test('a 500 is an unknown outcome too', () async {
      expect(
        await answer(const FakeGremioResponse(null, statusCode: 500)),
        isA<SubmissionOutcomeUnknown>(),
      );
    });

    test('a success without a usable status link is not a success', () async {
      expect(
        await answer(
          const FakeGremioResponse(<String, dynamic>{
            'receiptPdfUrl': kFakeReceiptUrl,
            'number': 'F_1',
          }, statusCode: 201),
        ),
        isA<SubmissionFailed>(),
      );
    });

    test('a link pointing at another origin is refused', () async {
      // The attack this closes: the endpoint answers with somebody else's host
      // and the app then sends the token there.
      expect(
        await answer(
          const FakeGremioResponse(<String, dynamic>{
            'statusUrl': 'https://attacker.invalid/status/abc',
            'receiptPdfUrl': kFakeReceiptUrl,
            'number': null,
          }, statusCode: 201),
        ),
        isA<SubmissionFailed>(),
      );
    });

    test('an http link is refused as well', () async {
      expect(
        await answer(
          const FakeGremioResponse(<String, dynamic>{
            'statusUrl': 'http://gremio.example/status/abc',
            'receiptPdfUrl': kFakeReceiptUrl,
            'number': null,
          }, statusCode: 201),
        ),
        isA<SubmissionFailed>(),
      );
    });
  });

  group('a build without an endpoint', () {
    test('reports "not connected" instead of pretending', () async {
      final FakeAttachmentStore store = FakeAttachmentStore();
      final GremioRequestGateway gateway = GremioRequestGateway(
        dio: fakeGremioDio(FakeGremioAdapter((_) => _created)),
        baseUrl: '',
        attachments: store,
      );

      expect(
        await gateway.submitFeedback(_feedback()),
        isA<SubmissionNotConnected>(),
      );
      expect(
        await gateway.submitApplication(await _application(store)),
        isA<SubmissionNotConnected>(),
      );
    });

    test('a plain-http base address counts as unconfigured', () async {
      final GremioRequestGateway gateway = GremioRequestGateway(
        dio: fakeGremioDio(FakeGremioAdapter((_) => _created)),
        baseUrl: 'http://gremio.example',
        attachments: FakeAttachmentStore(),
      );

      expect(
        await gateway.submitFeedback(_feedback()),
        isA<SubmissionNotConnected>(),
      );
    });
  });

  group('secrets', () {
    test('no failure reason ever carries a link or personal data', () async {
      for (final FakeGremioResponse response in <FakeGremioResponse>[
        const FakeGremioResponse.transportError(),
        const FakeGremioResponse(null, statusCode: 500),
        const FakeGremioResponse(<String, dynamic>{
          'statusUrl': 'https://attacker.invalid/status/abc',
          'receiptPdfUrl': kFakeReceiptUrl,
          'number': null,
        }, statusCode: 201),
      ]) {
        final (gateway, _, _) = await _build((_) => response);
        final SubmissionResult result = await gateway.submitFeedback(
          _feedback(submitterName: 'Max Mustermann'),
        );
        final String reason = switch (result) {
          SubmissionOutcomeUnknown(:final String reason) => reason,
          SubmissionFailed(:final String reason) => reason,
          _ => '',
        };
        expect(reason, isNot(contains('testtoken')));
        expect(reason, isNot(contains('attacker')));
        expect(reason, isNot(contains('Max')));
      }
    });
  });
}
