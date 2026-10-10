// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The rules that decide whether a student loses work, or files something
/// twice.
library;

import 'dart:typed_data';

import 'package:campus_koethen/features/requests/application/case_status_controller.dart';
import 'package:campus_koethen/features/requests/application/requests_controller.dart';
import 'package:campus_koethen/features/requests/application/requests_providers.dart';
import 'package:campus_koethen/features/requests/application/submissions_controller.dart';
import 'package:campus_koethen/features/requests/data/attachment_picker.dart';
import 'package:campus_koethen/features/requests/data/encrypted_request_store.dart';
import 'package:campus_koethen/features/requests/domain/application_files.dart';
import 'package:campus_koethen/features/requests/domain/case_status.dart';
import 'package:campus_koethen/features/requests/domain/request_drafts.dart';
import 'package:campus_koethen/features/requests/domain/request_gateway.dart';
import 'package:campus_koethen/features/requests/domain/status_gateway.dart';
import 'package:campus_koethen/features/requests/domain/submitted_case.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_gremio.dart';

final DateTime _now = DateTime(2026, 8, 6, 12);

const SubmissionAccepted _accepted = SubmissionAccepted(
  statusUrl: kFakeStatusUrl,
  receiptPdfUrl: kFakeReceiptUrl,
  number: 'A_0042_2026',
  wasReplay: false,
);

ProviderContainer _container({
  required FlakyRequestStore store,
  required ScriptedRequestGateway gateway,
  required FakeAttachmentStore attachments,
  ScriptedStatusGateway? status,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      requestStoreProvider.overrideWithValue(store),
      requestGatewayProvider.overrideWithValue(gateway),
      attachmentStoreProvider.overrideWithValue(attachments),
      if (status != null) statusGatewayProvider.overrideWithValue(status),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<FeedbackDraft> _feedbackDraft(ProviderContainer container) async {
  await container.read(requestsProvider.future);
  final FeedbackDraft draft = container
      .read(requestsProvider.notifier)
      .createFeedback(now: _now)
      .copyWith(areaId: 1, feedback: 'Ein Hinweis.');
  await container.read(requestsProvider.notifier).save(draft, now: _now);
  return draft;
}

void main() {
  group('a successful submission', () {
    test('records the case BEFORE the draft is removed', () async {
      final FlakyRequestStore store = FlakyRequestStore();
      final ScriptedRequestGateway gateway = ScriptedRequestGateway(_accepted);
      final ProviderContainer container = _container(
        store: store,
        gateway: gateway,
        attachments: FakeAttachmentStore(),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);
      await container.read(submissionsProvider.future);

      final SubmitOutcome outcome = await container
          .read(requestsProvider.notifier)
          .submit(draft, now: _now);

      expect(outcome, isA<SubmitRecorded>());
      expect(store.cases, hasLength(1));
      expect(store.cases.single.statusUrl, kFakeStatusUrl);
      expect(store.drafts, isEmpty);
    });

    test('keeps the draft when the case cannot be stored', () async {
      // The worst case: the committee has it, and the only way back may be
      // lost. Deleting the draft here would throw away the retry as well.
      final FlakyRequestStore store = FlakyRequestStore(failCaseWrites: true);
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);
      await container.read(submissionsProvider.future);

      final SubmitOutcome outcome = await container
          .read(requestsProvider.notifier)
          .submit(draft, now: _now);

      expect(outcome, isA<SubmitStoreFailed>());
      expect(store.drafts, hasLength(1));
      expect(store.drafts.single.id, draft.id);
    });

    test('deletes the attachments only after the case is recorded', () async {
      final FakeAttachmentStore attachments = FakeAttachmentStore();
      final FlakyRequestStore store = FlakyRequestStore();
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: attachments,
      );
      await container.read(requestsProvider.future);
      await container.read(submissionsProvider.future);

      final RequestAttachment file = (await attachments.put(
        'antrag.pdf',
        Uint8List.fromList(<int>[1]),
      ))!;
      final RequestAttachment card = (await attachments.put(
        'ausweis.pdf',
        Uint8List.fromList(<int>[2]),
      ))!;
      final FinanceApplicationDraft draft = container
          .read(requestsProvider.notifier)
          .createApplication(now: _now)
          .copyWith(
            locationId: 1,
            title: 'Titel',
            applicant: 'Person',
            files: <ApplicationFileSlot, RequestAttachment>{
              ApplicationFileSlot.financeRequest: file,
              ApplicationFileSlot.studentCard: card,
            },
          );
      await container.read(requestsProvider.notifier).save(draft, now: _now);

      await container.read(requestsProvider.notifier).submit(draft, now: _now);

      expect(store.cases, hasLength(1));
      expect(
        attachments.entries,
        isEmpty,
        reason: 'the student card must not linger once it has been sent',
      );
    });
  });

  group('a failed submission', () {
    test('loses nothing the user typed', () async {
      final FlakyRequestStore store = FlakyRequestStore();
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(
          const SubmissionRejected(message: 'Bitte Feedback eingeben.'),
        ),
        attachments: FakeAttachmentStore(),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);

      await container.read(requestsProvider.notifier).submit(draft, now: _now);

      expect(store.drafts, hasLength(1));
      expect((store.drafts.single as FeedbackDraft).feedback, 'Ein Hinweis.');
      expect(store.cases, isEmpty);
    });

    test('keeps the attachments of a rejected application', () async {
      final FakeAttachmentStore attachments = FakeAttachmentStore();
      final ProviderContainer container = _container(
        store: FlakyRequestStore(),
        gateway: ScriptedRequestGateway(const SubmissionTooLarge()),
        attachments: attachments,
      );
      await container.read(requestsProvider.future);
      final RequestAttachment file = (await attachments.put(
        'antrag.pdf',
        Uint8List.fromList(<int>[1]),
      ))!;
      final FinanceApplicationDraft draft = container
          .read(requestsProvider.notifier)
          .createApplication(now: _now)
          .copyWith(
            locationId: 1,
            title: 'T',
            applicant: 'P',
            files: <ApplicationFileSlot, RequestAttachment>{
              ApplicationFileSlot.financeRequest: file,
            },
          );
      await container.read(requestsProvider.notifier).save(draft, now: _now);

      await container.read(requestsProvider.notifier).submit(draft, now: _now);

      expect(attachments.entries, isNotEmpty);
    });
  });

  group('an ambiguous send attempt', () {
    Future<(ProviderContainer, FlakyRequestStore, ScriptedRequestGateway)>
    setUpFrozen() async {
      final FlakyRequestStore store = FlakyRequestStore();
      final ScriptedRequestGateway gateway = ScriptedRequestGateway(
        const SubmissionOutcomeUnknown('transport'),
      );
      final ProviderContainer container = _container(
        store: store,
        gateway: gateway,
        attachments: FakeAttachmentStore(),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);
      await container.read(requestsProvider.notifier).submit(draft, now: _now);
      return (container, store, gateway);
    }

    test('freezes the draft so its payload cannot drift', () async {
      final (container, store, _) = await setUpFrozen();

      expect(store.drafts.single.isFrozen, isTrue);
      expect(store.drafts.single.pending!.firstAttemptAt, _now);

      // An edit is refused rather than silently changing the retry payload.
      final FeedbackDraft frozen = store.drafts.single as FeedbackDraft;
      await container
          .read(requestsProvider.notifier)
          .save(frozen.copyWith(feedback: 'Anderer Text'), now: _now);

      expect((store.drafts.single as FeedbackDraft).feedback, 'Ein Hinweis.');
    });

    test('a retry reuses the same key and the same payload', () async {
      final (container, store, gateway) = await setUpFrozen();
      gateway.result = _accepted;

      await container
          .read(requestsProvider.notifier)
          .submit(store.drafts.single, now: _now.add(const Duration(hours: 1)));

      expect(gateway.keysUsed, hasLength(2));
      expect(gateway.keysUsed.first, gateway.keysUsed.last);
      expect(gateway.fingerprints.first, gateway.fingerprints.last);
    });

    test('a second ambiguous attempt keeps the FIRST attempt time', () async {
      // The server measures the 30 days from the original — a later retry must
      // not silently extend the window.
      final (container, store, _) = await setUpFrozen();

      await container
          .read(requestsProvider.notifier)
          .submit(store.drafts.single, now: _now.add(const Duration(days: 2)));

      expect(store.drafts.single.pending!.firstAttemptAt, _now);
    });

    test('stops instead of sending once the key is 30 days old', () async {
      final (container, store, gateway) = await setUpFrozen();
      gateway.result = _accepted;
      final int before = gateway.keysUsed.length;

      final SubmitOutcome outcome = await container
          .read(requestsProvider.notifier)
          .submit(store.drafts.single, now: _now.add(const Duration(days: 31)));

      expect(outcome, isA<SubmitKeyExpired>());
      expect(
        gateway.keysUsed.length,
        before,
        reason: 'nothing may go out that could become a second case',
      );
      expect(store.cases, isEmpty);
    });

    test('refuses to send when a frozen payload no longer matches', () async {
      final (container, store, gateway) = await setUpFrozen();
      gateway.result = _accepted;
      final FeedbackDraft frozen = store.drafts.single as FeedbackDraft;
      final int before = gateway.keysUsed.length;

      // Simulates a bug that mutated a frozen draft.
      final SubmitOutcome outcome = await container
          .read(requestsProvider.notifier)
          .submit(frozen.copyWith(feedback: 'Verändert'), now: _now);

      expect(outcome, isA<SubmitPayloadChanged>());
      expect(gateway.keysUsed.length, before);
    });

    test('can be released deliberately, which is the only way on', () async {
      final (container, store, _) = await setUpFrozen();

      await container
          .read(requestsProvider.notifier)
          .unfreeze(store.drafts.single.id);

      expect(store.drafts.single.isFrozen, isFalse);
    });
  });

  group('storage that cannot be read (E-03)', () {
    SubmittedCase storedCase(String id) => SubmittedCase(
      id: id,
      kind: RequestKind.feedback,
      submittedAt: _now,
      statusUrl: kFakeStatusUrl,
      receiptPdfUrl: kFakeReceiptUrl,
    );

    test('an unreadable case list is an error, never an empty list', () async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[storedCase('old-case')]
        ..failCaseReads = true;
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
      );

      await expectLater(
        container.read(submissionsProvider.future),
        throwsA(isA<RequestStoreUnavailable>()),
      );
    });

    test('a case is never added over a list that failed to load', () async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[storedCase('old-case')]
        ..failCaseReads = true;
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
      );
      await expectLater(
        container.read(submissionsProvider.future),
        throwsA(isA<RequestStoreUnavailable>()),
      );

      // The disk recovers, but the screen still holds the failed load.
      store.failCaseReads = false;
      final SubmissionsController notifier = container.read(
        submissionsProvider.notifier,
      );
      await expectLater(
        notifier.add(storedCase('new-case')),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      await expectLater(
        notifier.remove('old-case'),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      expect(store.caseWrites, 0);
      expect(store.cases.single.id, 'old-case');
    });

    test('a case added during the first load keeps the stored ones', () async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..cases = <SubmittedCase>[storedCase('old-case')]
        ..readDelay = const Duration(milliseconds: 20);
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
      );

      // No `await ...future` first: the form submits while the list is
      // still being read.
      await container
          .read(submissionsProvider.notifier)
          .add(storedCase('new-case'));

      expect(store.cases.map((SubmittedCase c) => c.id).toSet(), <String>{
        'old-case',
        'new-case',
      });
    });

    test('concurrent writes never lose a case', () async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..writeDelay = const Duration(milliseconds: 10);
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
      );
      await container.read(submissionsProvider.future);
      final SubmissionsController notifier = container.read(
        submissionsProvider.notifier,
      );
      await notifier.add(storedCase('a'));

      // A submission landing while a status refresh notes the case number.
      await Future.wait(<Future<void>>[
        notifier.add(storedCase('b')),
        notifier.noteServerFacts('a', number: 'A_1'),
        notifier.add(storedCase('c')),
      ]);

      expect(store.cases.map((SubmittedCase c) => c.id).toSet(), <String>{
        'a',
        'b',
        'c',
      });
      expect(
        store.cases.firstWhere((SubmittedCase c) => c.id == 'a').number,
        'A_1',
      );
    });

    test('a draft is never saved over drafts that failed to load', () async {
      final FlakyRequestStore store = FlakyRequestStore()
        ..failDraftReads = true;
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
      );
      await expectLater(
        container.read(requestsProvider.future),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      store.failDraftReads = false;

      final RequestsController notifier = container.read(
        requestsProvider.notifier,
      );
      final FeedbackDraft draft = notifier
          .createFeedback(now: _now)
          .copyWith(areaId: 1, feedback: 'Neu.');
      await expectLater(
        notifier.save(draft, now: _now),
        throwsA(isA<RequestStoreUnavailable>()),
      );
      expect(store.draftWrites, 0);
    });

    test('nothing is sent while the case list cannot be read', () async {
      // Sending first and failing to record afterwards would strand the one
      // status link the endpoint hands out.
      final FlakyRequestStore store = FlakyRequestStore()..failCaseReads = true;
      final ScriptedRequestGateway gateway = ScriptedRequestGateway(_accepted);
      final ProviderContainer container = _container(
        store: store,
        gateway: gateway,
        attachments: FakeAttachmentStore(),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);

      final SubmitOutcome outcome = await container
          .read(requestsProvider.notifier)
          .submit(draft, now: _now);

      expect(outcome, isA<SubmitStoreUnavailable>());
      expect(gateway.keysUsed, isEmpty);
      expect(store.drafts.single.isFrozen, isFalse);
    });
  });

  group('the status controller', () {
    SubmittedCase caseOf(String id) => SubmittedCase(
      id: id,
      kind: RequestKind.financeApplication,
      submittedAt: _now,
      statusUrl: kFakeStatusUrl,
      receiptPdfUrl: kFakeReceiptUrl,
    );

    test('joins concurrent requests for the same case into one', () async {
      final ScriptedStatusGateway status = ScriptedStatusGateway(
        StatusLoaded(_loadedStatus()),
        delay: const Duration(milliseconds: 20),
      );
      final ProviderContainer container = _container(
        store: FlakyRequestStore(),
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: status,
      );
      await container.read(submissionsProvider.future);

      final CaseStatusController controller = container.read(
        caseStatusProvider.notifier,
      );
      await Future.wait(<Future<StatusResult>>[
        controller.refresh(caseOf('a'), now: _now),
        controller.refresh(caseOf('a'), now: _now),
        controller.refresh(caseOf('a'), now: _now),
      ]);

      expect(status.calls, 1, reason: 'single flight');
    });

    test('sends the stored link, and only that', () async {
      final ScriptedStatusGateway status = ScriptedStatusGateway(
        StatusLoaded(_loadedStatus()),
      );
      final ProviderContainer container = _container(
        store: FlakyRequestStore(),
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: status,
      );
      await container.read(submissionsProvider.future);

      await container
          .read(caseStatusProvider.notifier)
          .refresh(caseOf('a'), now: _now);

      expect(status.urls, <String>[kFakeStatusUrl]);
    });

    test('honours Retry-After and stops asking until it passes', () async {
      final ScriptedStatusGateway status = ScriptedStatusGateway(
        const StatusRateLimited(retryAfter: Duration(seconds: 60)),
      );
      final ProviderContainer container = _container(
        store: FlakyRequestStore(),
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: status,
      );
      await container.read(submissionsProvider.future);
      final CaseStatusController controller = container.read(
        caseStatusProvider.notifier,
      );

      await controller.refresh(caseOf('a'), now: _now);
      expect(status.calls, 1);

      // Inside the window: nothing goes out.
      await controller.refresh(
        caseOf('a'),
        now: _now.add(const Duration(seconds: 30)),
      );
      expect(status.calls, 1);

      // After it: allowed again.
      await controller.refresh(
        caseOf('a'),
        now: _now.add(const Duration(seconds: 61)),
      );
      expect(status.calls, 2);
    });

    test('refreshes many cases at a bounded concurrency', () async {
      int running = 0;
      int peak = 0;
      final ScriptedStatusGateway status = _CountingStatusGateway(
        onStart: () {
          running++;
          if (running > peak) peak = running;
        },
        onEnd: () => running--,
      );
      final ProviderContainer container = _container(
        store: FlakyRequestStore(),
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: status,
      );
      await container.read(submissionsProvider.future);

      await container.read(caseStatusProvider.notifier).refreshAll(
        <SubmittedCase>[for (int i = 0; i < 9; i++) caseOf('case-$i')],
        now: _now,
      );

      expect(status.calls, 9);
      expect(
        peak,
        lessThanOrEqualTo(CaseStatusController.maxConcurrentRefreshes),
      );
    });

    test('keeps a loaded status when a later refresh fails', () async {
      final ScriptedStatusGateway status = ScriptedStatusGateway(
        StatusLoaded(_loadedStatus()),
      );
      final ProviderContainer container = _container(
        store: FlakyRequestStore(),
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: status,
      );
      await container.read(submissionsProvider.future);
      final CaseStatusController controller = container.read(
        caseStatusProvider.notifier,
      );

      await controller.refresh(caseOf('a'), now: _now);
      status.result = const StatusUnavailable('transport');
      await controller.refresh(
        caseOf('a'),
        now: _now.add(const Duration(minutes: 5)),
      );

      // A failed refresh must not blank a screen the user is reading.
      expect(controller.stateFor('a').hasStatus, isTrue);
      expect(controller.stateFor('a').error, isA<StatusUnavailable>());
    });
  });

  group('storage', () {
    test('a status response is never written to disk', () async {
      // The endpoint answers `no-store`. Only the number and title — neither
      // secret — are kept, so the list reads sensibly offline.
      final FlakyRequestStore store = FlakyRequestStore();
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: ScriptedStatusGateway(StatusLoaded(_loadedStatus())),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);
      await container.read(submissionsProvider.future);
      await container.read(requestsProvider.notifier).submit(draft, now: _now);

      await container
          .read(caseStatusProvider.notifier)
          .refresh(store.cases.single, now: _now);

      final Map<String, dynamic> stored = store.cases.single.toJson();
      expect(stored.containsKey('status'), isFalse);
      expect(stored.containsKey('publicNote'), isFalse);
      expect(stored.containsKey('documents'), isFalse);
    });

    test('forgetting a case takes its cached status with it', () async {
      final FlakyRequestStore store = FlakyRequestStore();
      final ProviderContainer container = _container(
        store: store,
        gateway: ScriptedRequestGateway(_accepted),
        attachments: FakeAttachmentStore(),
        status: ScriptedStatusGateway(StatusLoaded(_loadedStatus())),
      );
      final FeedbackDraft draft = await _feedbackDraft(container);
      await container.read(submissionsProvider.future);
      await container.read(requestsProvider.notifier).submit(draft, now: _now);
      final String id = store.cases.single.id;
      await container
          .read(caseStatusProvider.notifier)
          .refresh(store.cases.single, now: _now);

      await container.read(submissionsProvider.notifier).remove(id);
      container.read(caseStatusProvider.notifier).forget(id);

      expect(store.cases, isEmpty);
      expect(
        container.read(caseStatusProvider.notifier).stateFor(id).hasStatus,
        isFalse,
      );
    });
  });
}

/// A parsed application status, built from the documented example body.
CaseStatus _loadedStatus() => CaseStatus.fromJson(applicationStatusBody())!;

/// A gateway that reports when a call starts and ends, for concurrency tests.
class _CountingStatusGateway extends ScriptedStatusGateway {
  _CountingStatusGateway({required this.onStart, required this.onEnd})
    : super(const StatusUnavailable('n/a'));

  final void Function() onStart;
  final void Function() onEnd;

  @override
  Future<StatusResult> fetch(String statusUrl) async {
    calls++;
    onStart();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    onEnd();
    return const StatusUnavailable('n/a');
  }
}
