// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:meta/meta.dart';

/// A classified failure of the read-only HISinOne student-service functions
/// (Bescheinigungen, Personendaten/Kontaktdaten, Studiengangsübersicht).
///
/// Deliberately coarse and user-oriented, the same contract as [GradeFailure]:
/// never the session, cookies, tokens or any HTML response — only the
/// classification travels.
enum StudentServiceFailureKind {
  /// Grades is not connected, or the connected portal is HIS-QIS rather than
  /// HISinOne — this feature has nothing to read without a HISinOne session.
  notConnected,

  /// The stored grade credentials were rejected. Rare: it means the password
  /// changed on the portal's side after grades last verified it.
  invalidCredentials,

  /// A non-HTTPS URL or a host other than one of the two explicitly pinned
  /// origins (the portal itself, or the one-time document-download host) —
  /// refused.
  tlsOrHostRejected,

  /// The portal answered with a server error / is down.
  portalUnavailable,

  /// The expected HTML structure (a tab, a field, a button) was not
  /// recognised — the portal likely changed.
  portalStructureChanged,
  timeout,
  networkUnavailable,

  /// The encrypted local cache could not be opened.
  cacheUnavailable,

  /// A document exceeded the in-memory preview budget.
  documentTooLarge,

  /// A document could not be fetched for a reason short of the above.
  documentUnavailable,

  /// Anything not otherwise classified.
  unknown,
}

@immutable
class StudentServiceFailure implements Exception {
  const StudentServiceFailure(this.kind, {this.stage});

  final StudentServiceFailureKind kind;

  /// Which specific structural expectation failed (e.g. `'personalData'`,
  /// `'tabSwitch:report'`) — a fixed, hand-written label, never raw HTML, a
  /// URL fragment or anything read from the portal. Diagnostic only: it never
  /// reaches the user-facing message (`studentServiceFailureMessage` switches
  /// on [kind] alone), it only appears in [toString], so a developer reading
  /// a debug log can tell which real-portal check actually failed without
  /// any one failure report being able to leak session content.
  final String? stage;

  @override
  String toString() =>
      'StudentServiceFailure(${kind.name}${stage == null ? '' : ', stage: $stage'})';

  @override
  bool operator ==(Object other) =>
      other is StudentServiceFailure && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}
