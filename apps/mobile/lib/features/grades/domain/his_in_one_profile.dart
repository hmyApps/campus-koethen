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

  static const String _examOverviewPath =
      '/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml';

  /// The exam overview page (tree, collapsed on load).
  String get examOverviewUrl =>
      'https://sscportal.ssc.hs-anhalt.de$_examOverviewPath'
      '?_flowId=examsOverviewForPerson-flow';

  @override
  bool allows(Uri uri) => gradePortalAllows(uri, scheme: scheme, host: host);

  /// The SEPARATE host the one-time download redirects to — the same
  /// underlying document-download mechanism used by the Studienservice
  /// certificates, confirmed there 2026-10-04 from a real `Location` header
  /// (independently corroborated by the portal's own `Content-Security-
  /// Policy` response header, which lists this exact host under
  /// `child-src`). Never folded into [host]: the print button's own link
  /// stays on the portal host; only the redirect target this constant pins
  /// is on this separate subdomain.
  static const String documentDownloadHost =
      'untrust-sscportal.ssc.hs-anhalt.de';

  /// A second, narrower, ORDERED allowlist for exactly one purpose: every
  /// redirect hop a print button's POST can lead through, down to the
  /// one-time document itself — kept as its own check (never folded into
  /// [allows] by reference) so a future real difference would not require
  /// re-threading every session call site (AGENTS.md §2: "kein gemeinsamer
  /// Pool"). Deliberately NOT shared with
  /// `StudentServiceProfile.documentDownloadRoute`, even though both
  /// currently pin the same two hosts — separate features, separate checks.
  ///
  /// The real chain, confirmed 2026-10-04 from the device: the POST's own
  /// redirect bounces back through the exam-overview page itself on [host]
  /// (a standard POST/redirect/GET) — THAT page's own response is what then
  /// redirects to `/qisserver/rds?state=docdownload` on [host], which in
  /// turn redirects to [documentDownloadHost]. Returns a fresh check for ONE
  /// download, called once per redirect hop in order:
  ///
  ///  1. until the docdownload entry: the exam-overview page's own path on
  ///     [host] (the bounce, nothing more — not an arbitrary other page) or
  ///     the `state=docdownload` entry on [host];
  ///  2. after that entry: only `state=docdownload` on
  ///     [documentDownloadHost] — never back to [host], never the bounce.
  ///
  /// AGENTS.md §2 pins exactly this order; a flat "either host at any hop"
  /// set accepted a POST redirecting straight to the untrust- host.
  bool Function(Uri uri) examReportDownloadRoute() {
    bool entered = false;
    return (Uri uri) {
      if (!entered) {
        if (_isDocDownloadRequest(uri, host)) {
          entered = true;
          return true;
        }
        return gradePortalAllows(uri, scheme: scheme, host: host) &&
            uri.path == _examOverviewPath;
      }
      return _isDocDownloadRequest(uri, documentDownloadHost);
    };
  }

  bool _isDocDownloadRequest(Uri uri, String expectedHost) {
    final List<String>? states = uri.queryParametersAll['state'];
    return gradePortalAllows(uri, scheme: scheme, host: expectedHost) &&
        uri.path == '/qisserver/rds' &&
        !uri.hasFragment &&
        states != null &&
        states.length == 1 &&
        states.single == 'docdownload';
  }
}
