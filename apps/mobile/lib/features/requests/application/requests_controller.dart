// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachment_picker.dart';
import '../domain/application_files.dart';
import '../domain/attachment_store.dart';
import '../domain/idempotency_key.dart';
import '../domain/request_drafts.dart';
import '../domain/request_gateway.dart';
import '../domain/request_store.dart';
import '../domain/submitted_case.dart';
import 'requests_providers.dart';
import 'submissions_controller.dart';

/// What an attempt to submit ended in, from the app's point of view.
///
/// Wraps the gateway's answer with the two outcomes only this layer can
/// produce: the case was safely recorded, or the endpoint accepted it and the
/// device could not keep the link.
sealed class SubmitOutcome {
  const SubmitOutcome();
}

/// Accepted **and** stored. The draft is gone; the case is trackable.
class SubmitRecorded extends SubmitOutcome {
  const SubmitRecorded(this.submitted);

  final SubmittedCase submitted;
}

/// The endpoint accepted it, but local storage refused to keep the link.
///
/// The worst case in this whole area: the case exists and the only way back to
/// it may be lost. The draft is deliberately **kept** — with its key, so a
/// retry replays rather than files a second one — and the user is told
/// plainly.
class SubmitStoreFailed extends SubmitOutcome {
  const SubmitStoreFailed();
}

/// Nothing was sent: the stored case list could not be read.
///
/// Sending first and then failing to record the answer would strand the one
/// status link the endpoint hands out, so the attempt stops before the
/// network is touched.
class SubmitStoreUnavailable extends SubmitOutcome {
  const SubmitStoreUnavailable();
}

/// Everything the gateway itself reported.
class SubmitGatewaySaid extends SubmitOutcome {
  const SubmitGatewaySaid(this.result);

  final SubmissionResult result;
}

/// The draft is frozen after an ambiguous attempt and its key has outlived the
/// server's 30-day retention.
///
/// Sending now would file a **second** case, and generating a fresh key would
/// do the same thing while hiding it. So the app does neither on its own: it
/// stops and asks.
class SubmitKeyExpired extends SubmitOutcome {
  const SubmitKeyExpired(this.firstAttemptAt);

  final DateTime firstAttemptAt;
}

/// The frozen draft no longer matches what was sent.
///
/// Should be unreachable — the editor refuses edits while frozen — so this is
/// the guard that turns a bug into a stop rather than a duplicate case.
class SubmitPayloadChanged extends SubmitOutcome {
  const SubmitPayloadChanged();
}

/// Locally stored drafts, newest first.
class RequestsController extends AsyncNotifier<List<RequestDraft>> {
  RequestStore get _store => ref.read(requestStoreProvider);
  AttachmentStore get _attachments => ref.read(attachmentStoreProvider);

  @override
  Future<List<RequestDraft>> build() async =>
      _sorted(await _store.readDrafts());

  static List<RequestDraft> _sorted(List<RequestDraft> drafts) =>
      drafts.toList()..sort(
        (RequestDraft a, RequestDraft b) => b.updatedAt.compareTo(a.updatedAt),
      );

  List<RequestDraft> get _current => state.value ?? const <RequestDraft>[];

  /// The stored drafts — waiting for a load in progress, refusing a failed
  /// one. Writing an empty stand-in would replace every stored draft.
  Future<List<RequestDraft>> _loaded() async {
    try {
      await future;
    } catch (_) {
      throw const RequestStoreUnavailable();
    }
    final AsyncValue<List<RequestDraft>> current = state;
    if (current.hasError || !current.hasValue) {
      throw const RequestStoreUnavailable();
    }
    return current.requireValue;
  }

  RequestDraft? byId(String id) {
    for (final RequestDraft draft in _current) {
      if (draft.id == id) return draft;
    }
    return null;
  }

  /// Creates an empty application draft.
  ///
  /// Not persisted yet: an editor the user opens and immediately leaves should
  /// not litter the list with blanks. [save] is what writes.
  FinanceApplicationDraft createApplication({required DateTime now}) =>
      FinanceApplicationDraft(
        id: 'draft-${now.microsecondsSinceEpoch}',
        createdAt: now,
        updatedAt: now,
        // Once, here — so a retry after a timeout carries the same key and the
        // receiving system replays instead of filing a second application.
        idempotencyKey: IdempotencyKey.generate(),
      );

  FeedbackDraft createFeedback({required DateTime now}) => FeedbackDraft(
    id: 'draft-${now.microsecondsSinceEpoch}',
    createdAt: now,
    updatedAt: now,
    idempotencyKey: IdempotencyKey.generate(),
  );

  /// Inserts or replaces a draft.
  ///
  /// A completely blank draft is *removed* instead of stored — leaving the
  /// editor without typing anything should leave no trace. A **frozen** draft
  /// is refused: its bytes are the retry payload, and changing them under the
  /// same key is what turns a replay into a conflict or a duplicate.
  Future<void> save(RequestDraft draft, {required DateTime now}) async {
    final List<RequestDraft> current = await _loaded();
    final RequestDraft? existing = byId(draft.id);
    if (existing != null && existing.isFrozen) return;

    final List<RequestDraft> next = current
        .where((RequestDraft d) => d.id != draft.id)
        .toList();
    if (!draft.isEmpty) next.add(_touch(draft, now));
    await _persist(next);
  }

  static RequestDraft _touch(RequestDraft draft, DateTime now) =>
      switch (draft) {
        FinanceApplicationDraft() => draft.copyWith(updatedAt: now),
        FeedbackDraft() => draft.copyWith(updatedAt: now),
      };

  /// Deletes a draft and the attachments it owned.
  Future<void> delete(String id) async {
    final List<RequestDraft> current = await _loaded();
    final RequestDraft? draft = byId(id);
    await _persist(current.where((RequestDraft d) => d.id != id).toList());
    if (draft is FinanceApplicationDraft) {
      await _attachments.deleteAll(draft.files.values);
    }
  }

  /// Submits a draft and records the result.
  ///
  /// The order is the whole point:
  ///
  /// 1. send;
  /// 2. on success, **store the case first** — the status link is the only way
  ///    back and cannot be recovered from anywhere;
  /// 3. only then remove the draft;
  /// 4. only then delete its attachments.
  ///
  /// Any failure short of that leaves the draft and its files exactly where
  /// they were. Nothing the user typed or picked is ever lost to an error.
  Future<SubmitOutcome> submit(
    RequestDraft draft, {
    required DateTime now,
    SubmissionProgress? onProgress,
    SubmissionCancelToken? cancel,
  }) async {
    // Before anything goes out: an accepted case has to be recordable, and
    // the case list is what it is recorded into.
    try {
      await ref.read(submissionsProvider.future);
    } catch (_) {
      return const SubmitStoreUnavailable();
    }
    if (ref.read(submissionsProvider).hasError) {
      return const SubmitStoreUnavailable();
    }

    final PendingSubmission? pending = draft.pending;
    if (pending != null) {
      // A frozen draft may only be retried with byte-identical data.
      if (pending.fingerprint != draft.payloadFingerprint) {
        return const SubmitPayloadChanged();
      }
      if (pending.isExpiredAt(now)) {
        return SubmitKeyExpired(pending.firstAttemptAt);
      }
    }

    final RequestGateway gateway = ref.read(requestGatewayProvider);
    final SubmissionResult result = switch (draft) {
      FinanceApplicationDraft() => await gateway.submitApplication(
        draft,
        onProgress: onProgress,
        cancel: cancel,
      ),
      FeedbackDraft() => await gateway.submitFeedback(
        draft,
        onProgress: onProgress,
        cancel: cancel,
      ),
    };

    if (result is SubmissionAccepted) return _record(draft, result, now);

    if (result is SubmissionOutcomeUnknown) {
      // Freeze: the case may exist. The key and the exact payload have to
      // survive unchanged so a retry can replay instead of filing a second.
      await _freeze(draft, now);
    }
    return SubmitGatewaySaid(result);
  }

  Future<SubmitOutcome> _record(
    RequestDraft draft,
    SubmissionAccepted accepted,
    DateTime now,
  ) async {
    final SubmittedCase submitted = SubmittedCase(
      id: draft.id,
      kind: draft.kind,
      submittedAt: now,
      statusUrl: accepted.statusUrl,
      receiptPdfUrl: accepted.receiptPdfUrl,
      number: accepted.number,
      localTitle: switch (draft) {
        FinanceApplicationDraft() => draft.title.trim(),
        FeedbackDraft() => draft.feedback.trim(),
      },
      wasReplay: accepted.wasReplay,
    );

    try {
      await ref.read(submissionsProvider.notifier).add(submitted);
    } catch (_) {
      // ANY failure to store, not just the store's own exception type: the
      // case exists and its link may now be lost, so the draft — with its key
      // — is kept rather than deleted on the way past a crash.
      return const SubmitStoreFailed();
    }

    await _persist(
      _current.where((RequestDraft d) => d.id != draft.id).toList(),
    );
    if (draft is FinanceApplicationDraft) {
      // Safe now: the case is recorded, so these bytes are no longer the only
      // copy of anything that still has to be sent.
      await _attachments.deleteAll(draft.files.values);
    }
    return SubmitRecorded(submitted);
  }

  Future<void> _freeze(RequestDraft draft, DateTime now) async {
    final PendingSubmission pending = PendingSubmission(
      // The clock starts at the FIRST attempt: a later retry must not extend
      // a window the server measures from the original.
      firstAttemptAt: draft.pending?.firstAttemptAt ?? now,
      fingerprint: draft.payloadFingerprint,
    );
    final RequestDraft frozen = switch (draft) {
      FinanceApplicationDraft() => draft.copyWith(pending: pending),
      FeedbackDraft() => draft.copyWith(pending: pending),
    };
    await _persist(<RequestDraft>[
      ..._current.where((RequestDraft d) => d.id != draft.id),
      frozen,
    ]);
  }

  /// Lets the user abandon a frozen draft.
  ///
  /// Used when the key has expired and they decide the case never arrived.
  /// Deliberately explicit: this is the one path that can produce a duplicate,
  /// and it must be a decision rather than a side effect.
  Future<void> unfreeze(String id) async {
    final List<RequestDraft> current = await _loaded();
    final RequestDraft? draft = byId(id);
    if (draft == null) return;
    final RequestDraft thawed = switch (draft) {
      FinanceApplicationDraft() => draft.copyWith(clearPending: true),
      FeedbackDraft() => draft.copyWith(clearPending: true),
    };
    await _persist(<RequestDraft>[
      ...current.where((RequestDraft d) => d.id != id),
      thawed,
    ]);
  }

  Future<void> _persist(List<RequestDraft> drafts) async {
    final List<RequestDraft> sorted = _sorted(drafts);
    state = AsyncData<List<RequestDraft>>(sorted);
    await _store.writeDrafts(sorted);
  }
}

final AsyncNotifierProvider<RequestsController, List<RequestDraft>>
requestsProvider =
    AsyncNotifierProvider<RequestsController, List<RequestDraft>>(
      RequestsController.new,
      // A failed read stays an error the screen can show and retry, instead
      // of a "loading" state every write would wait on.
      retry: (_, _) => null,
    );

/// The file slots of an application, in form order.
const List<ApplicationFileSlot> kApplicationSlotOrder = <ApplicationFileSlot>[
  ApplicationFileSlot.financeRequest,
  ApplicationFileSlot.studentCard,
  ApplicationFileSlot.annexA,
  ApplicationFileSlot.annexB,
];
