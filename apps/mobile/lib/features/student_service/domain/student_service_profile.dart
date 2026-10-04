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
///    hands back, and the redirect it leads to. A 2026-10-01 analysis had
///    wrongly claimed that redirect points at a separate "untrust-"
///    subdomain; a 2026-10-04 attempt at a direct, hand-built request to
///    that subdomain failed, which was wrongly read as proof the subdomain
///    did not exist — it was simply missing the one-time, per-job
///    `accountId`/`hash`/`timestamp` the server requires. A REAL captured
///    download on 2026-10-04, this time from an actual completed job, shows
///    the true two-hop shape: the job's own link stays on the portal host
///    with only `docId`; its `307` then redirects to exactly this separate
///    `untrust-` host with the richer parameter set — independently
///    corroborated by the portal's own `Content-Security-Policy` response
///    header, which lists that exact host under `child-src`. Kept as its
///    own function regardless, never used for anything but that one fetch
///    (AGENTS.md §2: "kein gemeinsamer Pool") — a future real difference
///    must not require re-threading every call site.
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

  /// The SEPARATE host a generated certificate's download redirects to —
  /// confirmed 2026-10-04 (see the class doc comment). Never folded into
  /// [host]: the job's own link is on the portal host; only the redirect
  /// target this constant pins is on this separate subdomain.
  static const String documentDownloadHost =
      'untrust-sscportal.ssc.hs-anhalt.de';

  static bool allows(Uri uri) =>
      gradePortalAllows(uri, scheme: scheme, host: host);

  /// Accepts BOTH hops of the one-time document download: the job's own
  /// link on [host] (only `docId`), and the `307` redirect target on
  /// [documentDownloadHost] (the richer `accountId`/`hash`/`timestamp`/
  /// `docName` set). Neither hop's extra parameters are otherwise
  /// constrained — the state/path/scheme/port shape is what is pinned.
  static bool allowsDocumentDownload(Uri uri) {
    final List<String>? states = uri.queryParametersAll['state'];
    final bool hostAllowed =
        gradePortalAllows(uri, scheme: scheme, host: host) ||
        gradePortalAllows(uri, scheme: scheme, host: documentDownloadHost);
    return hostAllowed &&
        uri.path == '/qisserver/rds' &&
        !uri.hasFragment &&
        states != null &&
        states.length == 1 &&
        states.single == 'docdownload';
  }
}
