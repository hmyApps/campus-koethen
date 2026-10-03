// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../grades/domain/grade_portal_profile.dart' show gradePortalAllows;

/// The pinned endpoints of the read-only HISinOne student-service functions.
///
/// Two deliberately SEPARATE allowlist checks, never folded into one, even
/// though both now pin the same host:
///
///  - [allows] is the only host every piece of session traffic (login, the
///    "Studienservice" page, every tab-switch POST) may reach.
///  - [allowsDocumentDownload] is a second, narrower allowlist for exactly
///    one purpose: the one-time link a generated certificate's AJAX job
///    hands back. A 2026-10-01 analysis had wrongly claimed that link points
///    at a separate "untrust-" subdomain; a real captured download request
///    on 2026-10-04 confirmed it is the SAME host as the portal, just with
///    its own narrow path/query shape. Kept as its own function regardless,
///    never used for anything but that one fetch (AGENTS.md §2: "kein
///    gemeinsamer Pool") — a future real difference must not require
///    re-threading every call site.
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

  /// The host a generated certificate's one-time download link points at —
  /// the same host as the portal itself (see the class doc comment).
  static const String documentDownloadHost = host;

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
