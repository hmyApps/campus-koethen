// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/request_store.dart';
import '../domain/submitted_case.dart';
import 'requests_providers.dart';

/// The cases this device has submitted, newest first.
///
/// Local tracking only. There is no "my submissions" endpoint — the status
/// link *is* the account — so a case that is not in this list is unreachable
/// forever. That is why [add] must succeed before its draft is removed, and
/// why [remove] is a deliberate, warned-about action.
///
/// Every write is computed from the **loaded** list and runs after the one
/// before it has finished:
///
/// * while the list is still being read, a write waits for it;
/// * if it could not be read, a write is refused with
///   [RequestStoreUnavailable] — an empty stand-in would overwrite every
///   stored link;
/// * two writes never start from the same snapshot, so a submission landing
///   during a status refresh cannot drop the other's case.
class SubmissionsController extends AsyncNotifier<List<SubmittedCase>> {
  RequestStore get _store => ref.read(requestStoreProvider);

  Future<void> _tail = Future<void>.value();

  @override
  Future<List<SubmittedCase>> build() async =>
      _sorted(await _store.readCases());

  static List<SubmittedCase> _sorted(List<SubmittedCase> cases) =>
      cases.toList()..sort(
        (SubmittedCase a, SubmittedCase b) =>
            b.submittedAt.compareTo(a.submittedAt),
      );

  List<SubmittedCase> get _current => state.value ?? const <SubmittedCase>[];

  SubmittedCase? byId(String id) {
    for (final SubmittedCase item in _current) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Runs [mutation] against the loaded list, after every earlier one.
  Future<void> _serialized(
    Future<void> Function(List<SubmittedCase> current) mutation,
  ) {
    final Future<void> result = _tail.then(
      (_) async => mutation(await _loaded()),
    );
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// The stored list — waiting for a load in progress, refusing a failed one.
  Future<List<SubmittedCase>> _loaded() async {
    try {
      await future;
    } catch (_) {
      throw const RequestStoreUnavailable();
    }
    final AsyncValue<List<SubmittedCase>> current = state;
    if (current.hasError || !current.hasValue) {
      throw const RequestStoreUnavailable();
    }
    return current.requireValue;
  }

  void _publish(List<SubmittedCase> next) {
    if (ref.mounted) state = AsyncData<List<SubmittedCase>>(next);
  }

  /// Records a case. **Throws** when storage refused it.
  ///
  /// Deliberately not best-effort: the caller is about to delete the draft
  /// that produced this, and a silently dropped write would lose the only way
  /// back to the case.
  Future<void> add(SubmittedCase submitted) =>
      _serialized((List<SubmittedCase> current) async {
        final List<SubmittedCase> next = _sorted(<SubmittedCase>[
          ...current.where((SubmittedCase c) => c.id != submitted.id),
          submitted,
        ]);
        await _store.writeCases(next);
        _publish(next);
      });

  /// Forgets a case locally.
  ///
  /// The status link cannot be recovered — not by the app, not by the
  /// committee, not by e-mail. The UI warns before calling this.
  Future<void> remove(String id) =>
      _serialized((List<SubmittedCase> current) async {
        final List<SubmittedCase> next = _sorted(
          current.where((SubmittedCase c) => c.id != id).toList(),
        );
        await _store.writeCases(next);
        _publish(next);
      });

  /// Keeps locally known metadata in step with what the server reports.
  ///
  /// Only the case *number* and title, which are not secret and make the list
  /// readable offline. The status itself is never persisted: the endpoint
  /// answers `no-store`, and a stored status would be presented as current
  /// long after it stopped being true.
  Future<void> noteServerFacts(
    String id, {
    String? number,
    String? title,
  }) async {
    try {
      await _serialized((List<SubmittedCase> current) async {
        SubmittedCase? existing;
        for (final SubmittedCase item in current) {
          if (item.id == id) existing = item;
        }
        if (existing == null) return;
        if (existing.number == number && existing.localTitle == title) return;
        final SubmittedCase updated = existing.copyWith(
          number: number ?? existing.number,
          localTitle: (title ?? '').trim().isEmpty
              ? existing.localTitle
              : title,
        );
        final List<SubmittedCase> next = _sorted(<SubmittedCase>[
          ...current.where((SubmittedCase c) => c.id != id),
          updated,
        ]);
        _publish(next);
        await _store.writeCases(next);
      });
    } catch (_) {
      // Cosmetic data — a failed write here must not break the screen.
    }
  }
}

final AsyncNotifierProvider<SubmissionsController, List<SubmittedCase>>
submissionsProvider =
    AsyncNotifierProvider<SubmissionsController, List<SubmittedCase>>(
      SubmissionsController.new,
      // A list that cannot be read stays an error until the reader retries;
      // the screen offers that. Silent background retries would keep it
      // "loading", and every write waiting on it.
      retry: (_, _) => null,
    );
