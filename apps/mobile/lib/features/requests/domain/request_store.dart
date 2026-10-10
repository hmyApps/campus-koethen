// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'request_drafts.dart';
import 'submitted_case.dart';

/// Port: local, on-device persistence for drafts and submitted cases.
///
/// Everything behind this port is **encrypted at rest**. A draft can hold a
/// student card, and a submitted case holds a link that is equivalent to a
/// bearer token — neither belongs in SharedPreferences or a plaintext box.
///
/// Drafts and cases are user data, not a cache: nothing here is ever evicted
/// to make room, and a failed write is reported rather than swallowed, because
/// the caller has to know whether a case was safely recorded before it removes
/// the draft that produced it.
abstract interface class RequestStore {
  Future<List<RequestDraft>> readDrafts();
  Future<void> writeDrafts(List<RequestDraft> drafts);

  Future<List<SubmittedCase>> readCases();
  Future<void> writeCases(List<SubmittedCase> cases);

  /// Removes every draft and case from the device, together with the key
  /// they were encrypted with.
  ///
  /// Returns true only when the removal was verified. The caller reports the
  /// result to the user, so a partial wipe must never come back as success —
  /// what is left behind here is the copy of a student ID and the status
  /// links that are the only access to the submitted cases.
  Future<bool> wipeEverything();
}

/// Thrown when local storage could not keep — or could not read — what it
/// holds.
///
/// A failed read is reported with this rather than as an empty list: the
/// next write would otherwise replace every stored status link with whatever
/// the caller happened to hold.
class RequestStoreUnavailable implements Exception {
  const RequestStoreUnavailable();

  @override
  String toString() => 'RequestStoreUnavailable';
}

/// A volatile store, used as a safe fallback and in tests.
class InMemoryRequestStore implements RequestStore {
  List<RequestDraft> _drafts = const <RequestDraft>[];
  List<SubmittedCase> _cases = const <SubmittedCase>[];

  @override
  Future<bool> wipeEverything() async {
    _drafts = const <RequestDraft>[];
    _cases = const <SubmittedCase>[];
    return true;
  }

  @override
  Future<List<RequestDraft>> readDrafts() async =>
      List<RequestDraft>.of(_drafts);

  @override
  Future<void> writeDrafts(List<RequestDraft> drafts) async =>
      _drafts = List<RequestDraft>.of(drafts);

  @override
  Future<List<SubmittedCase>> readCases() async =>
      List<SubmittedCase>.of(_cases);

  @override
  Future<void> writeCases(List<SubmittedCase> cases) async =>
      _cases = List<SubmittedCase>.of(cases);
}
