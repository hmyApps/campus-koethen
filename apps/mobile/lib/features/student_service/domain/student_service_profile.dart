// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../grades/domain/grade_portal_profile.dart' show gradePortalAllows;

/// The pinned endpoints of the read-only HISinOne student-service functions.
///
/// Two deliberately SEPARATE allowlist checks, never folded into one:
///
///  - [allows] is the only host every piece of session traffic (login, the
///    "Studienservice" page, every tab-switch POST) may reach.
///  - [allowsDocumentDownload] is a second, narrower allowlist for exactly
///    one purpose: the one-time link a generated certificate's AJAX job
///    hands back. Real-portal analysis (2026-10-01) found that link points at
///    a DIFFERENT host than the portal itself — never widen [allows] to cover
///    it, and never use [allowsDocumentDownload] for anything but that one
///    fetch (AGENTS.md §2: "kein gemeinsamer Pool").
abstract final class StudentServiceProfile {
  static const String scheme = 'https';

  /// The only host session traffic may reach — identical to the HISinOne
  /// exam portal, because this is the same portal, not a separate one.
  static const String host = 'sscportal.ssc.hs-anhalt.de';

  static const String baseUrl = 'https://$host';

  /// The one page every function lives on, as five tabs of one JSF form.
  /// Tab-switching is a full form POST with a fresh `_flowExecutionKey`, not
  /// a distinct URL per tab.
  static const String studyServiceUrl =
      '$baseUrl/qisserver/pages/cm/stu/studyService/start.xhtml'
      '?_flowId=studyservice-flow';

  /// The host a generated certificate's one-time download link points at.
  /// Confirmed by real-portal analysis to differ from [host].
  static const String documentDownloadHost =
      'untrust-sscportal.ssc.hs-anhalt.de';

  static bool allows(Uri uri) =>
      gradePortalAllows(uri, scheme: scheme, host: host);

  static bool allowsDocumentDownload(Uri uri) {
    final List<String>? states = uri.queryParametersAll['state'];
    return gradePortalAllows(uri, scheme: scheme, host: documentDownloadHost) &&
        uri.path == '/qisserver/rds' &&
        !uri.hasFragment &&
        states != null &&
        states.length == 1 &&
        states.single == 'docdownload';
  }
}
