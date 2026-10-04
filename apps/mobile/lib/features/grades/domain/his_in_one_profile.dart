// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'grade_portal.dart';
import 'grade_portal_profile.dart';

/// The pinned HISinOne exam-portal endpoints of Hochschule Anhalt.
///
/// This is the single source of truth for the ONE host the HISinOne gateway is
/// allowed to talk to — deliberately a SEPARATE allowlist from the legacy
/// HIS-QIS portal ([LegacyQisProfile]).
class HisInOneProfile implements GradePortalProfile {
  const HisInOneProfile();

  @override
  GradePortal get portal => GradePortal.hisInOne;

  @override
  String get scheme => 'https';

  @override
  String get host => 'sscportal.ssc.hs-anhalt.de';

  @override
  String get baseUrl => 'https://sscportal.ssc.hs-anhalt.de';

  @override
  String get portalUrl =>
      'https://sscportal.ssc.hs-anhalt.de/qisserver/rds?state=user&type=0';

  @override
  String get loginUrl =>
      'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=user&type=1&category=auth.login';

  @override
  String get logoutUrl =>
      'https://sscportal.ssc.hs-anhalt.de/qisserver/rds'
      '?state=user&type=3&category=auth.logout';

  /// The exam overview page (tree, collapsed on load).
  String get examOverviewUrl =>
      'https://sscportal.ssc.hs-anhalt.de/qisserver/pages/sul/examAssessment/'
      'personExamsReadonly.xhtml?_flowId=examsOverviewForPerson-flow';

  @override
  bool allows(Uri uri) => gradePortalAllows(uri, scheme: scheme, host: host);

  /// A second, narrower allowlist for exactly one purpose: the one-time
  /// link one of the exam overview's own print buttons resolves to — same
  /// host as the portal itself, confirmed 2026-10-04, but kept as its own
  /// check (never folded into [allows]) so a future real difference would
  /// not require re-threading every session call site (AGENTS.md §2: "kein
  /// gemeinsamer Pool"). Deliberately NOT shared with
  /// `StudentServiceProfile.allowsDocumentDownload`, even though both
  /// currently pin the same values — separate features, separate checks.
  bool allowsDocumentDownload(Uri uri) {
    final List<String>? states = uri.queryParametersAll['state'];
    return gradePortalAllows(uri, scheme: scheme, host: host) &&
        uri.path == '/qisserver/rds' &&
        !uri.hasFragment &&
        states != null &&
        states.length == 1 &&
        states.single == 'docdownload';
  }
}
