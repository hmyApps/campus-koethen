// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'grade_portal.dart';

/// Persists WHICH exam portal an account was set up on, in the same secure
/// storage as the credentials — so "Noten-Verbindung und lokale Noten löschen"
/// removes the portal choice too, in the same step.
abstract interface class GradePortalStore {
  Future<GradePortal?> read();
  Future<void> write(GradePortal portal);
  Future<void> clear();
}
