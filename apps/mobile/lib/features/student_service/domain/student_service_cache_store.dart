// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'student_service_overview.dart';

/// Encrypted local store for the last successful Studienservice overview and
/// its sync timestamps — same contract as `GradeCacheStore`.
///
/// A generated certificate's bytes are deliberately NOT part of this store:
/// they are never archived, only held in memory for the duration of the
/// in-app open/share action in `StudentServiceScreen`/`DocumentViewerScreen`.
abstract interface class StudentServiceCacheStore {
  Future<StudentServiceOverview?> readOverview();
  Future<void> writeOverview(StudentServiceOverview overview);

  Future<DateTime?> readLastSuccessfulSync();
  Future<void> writeLastSuccessfulSync(DateTime at);

  Future<DateTime?> readLastAttemptedSync();
  Future<void> writeLastAttemptedSync(DateTime at);

  /// Wipes the overview, timestamps AND the encryption key.
  Future<void> clear();
}
