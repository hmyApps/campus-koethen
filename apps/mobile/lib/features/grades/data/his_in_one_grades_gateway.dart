// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:dio/dio.dart';

import '../domain/grade.dart';
import '../domain/grade_credentials.dart';
import '../domain/grade_failure.dart';
import '../domain/grade_portal_profile.dart';
import '../domain/grades_gateway.dart';
import 'his_in_one_html_parser.dart';
import 'his_in_one_session.dart';

/// Talks to the HISinOne exam portal over HTTPS, ONLY to the pinned host.
///
/// Same security posture as [LegacyQisGradesGateway], enforced independently
/// here (deliberately no shared allowlist):
///  - Every request URL is validated to be HTTPS on exactly the portal host; a
///    redirect to another host or to HTTP is refused (`tlsOrHostRejected`).
///  - Certificate validation is NEVER disabled.
///  - The cookie jar is in-memory and per fetch. In `finally` the logout
///    endpoint is called (best effort) and the jar is emptied.
///  - No dio LogInterceptor; credentials, cookies, `authenticity_token`,
///    `ViewState` and HTML are never logged.
///
/// The flow is at most four requests: login (POST), the exam overview (GET),
/// "expand all" (POST, with every hidden field taken from the loaded page —
/// nothing hard-coded, and only when that control exists in this portal
/// build), and logout (GET, `finally`).
class HisInOneGradesGateway implements GradesGateway {
  HisInOneGradesGateway(this._profile, [this._adapter]);

  final GradePortalProfile _profile;
  final HttpClientAdapter? _adapter;

  @override
  Future<GradeReport> fetchGrades(GradeCredentials credentials) async {
    final HisInOneSession session = HisInOneSession(
      baseUrl: _profile.baseUrl,
      allows: _profile.allows,
      adapter: _adapter,
    );

    try {
      // 1) Login. Positive authentication check: HISinOne renders a hidden
      // `sessionTimeoutLoginForm` (fields `asdf`/`fdsa`) on every page, even
      // when logged in, so testing for the login form's ABSENCE is always
      // false-positive on this portal. Only a logout link proves the session
      // actually authenticated.
      await session.login(
        loginUrl: _profile.loginUrl,
        username: credentials.username,
        password: credentials.password,
        successSignal: 'category=menu.browse',
        failureSignal: 'hisinoneStartPage.faces',
        isAuthenticated: HisInOneHtmlParser.isAuthenticated,
      );

      // 2) The (collapsed) exam overview.
      final HisInOnePage overview = await session.fetchPage(_examOverviewUrl());

      // 3) Decide what this page actually is before touching it. An account
      //    with no exam results on THIS portal renders the Leistungsdaten
      //    section with "Es wurden keine Datensätze gefunden" — no tree and no
      //    expand-all button. That is an EMPTY report, not a structure change:
      //    reporting it as a failure aborted setup before the other portal was
      //    ever tried, which is exactly how a working account ended up with no
      //    grades at all.
      final HisInOneOverview classified = await HisInOneHtmlParser.readOverview(
        overview.html,
      );
      switch (classified.kind) {
        case HisInOneOverviewKind.unrecognised:
          throw const GradeFailure(GradeFailureKind.portalStructureChanged);
        case HisInOneOverviewKind.empty:
          return const GradeReport(<GradeEntry>[]);
        case HisInOneOverviewKind.rendered:
          // No expand-all control in this portal build — parse as rendered.
          return await HisInOneHtmlParser.parseGradeReport(overview.html);
        case HisInOneOverviewKind.expandable:
          break;
      }

      // 4) Expand the tree: POST every hidden field from the loaded page plus
      //    the expand-all button, to the form's own action.
      final HisInOneExpandRequest expand = classified.expandRequest!;
      final HisInOnePage expanded = await session.postForm(
        expand.action,
        expand.formData,
      );

      // 5) Parse. If expanding emptied the section, that is still an empty
      //    report rather than a structure change.
      final HisInOneOverview afterExpand =
          await HisInOneHtmlParser.readOverview(expanded.html);
      if (afterExpand.kind == HisInOneOverviewKind.empty) {
        return const GradeReport(<GradeEntry>[]);
      }
      return await HisInOneHtmlParser.parseGradeReport(expanded.html);
    } on GradeFailure {
      rethrow;
    } on HisInOneSessionFailure catch (e) {
      throw _mapSessionFailure(e);
    } on DioException catch (e) {
      throw _mapSessionFailure(HisInOneSession.mapDioException(e));
    } catch (_) {
      // Never re-throw a raw error that could carry HTML or secrets.
      throw const GradeFailure(GradeFailureKind.unknown);
    } finally {
      await session.close(_profile.logoutUrl);
    }
  }

  String _examOverviewUrl() =>
      '${_profile.baseUrl}/qisserver/pages/sul/examAssessment/'
      'personExamsReadonly.xhtml?_flowId=examsOverviewForPerson-flow';

  static GradeFailure _mapSessionFailure(HisInOneSessionFailure e) {
    switch (e.kind) {
      case HisInOneSessionFailureKind.hostRejected:
        return const GradeFailure(GradeFailureKind.tlsOrHostRejected);
      case HisInOneSessionFailureKind.unavailable:
        return const GradeFailure(GradeFailureKind.portalUnavailable);
      case HisInOneSessionFailureKind.loginRejected:
        return const GradeFailure(GradeFailureKind.invalidCredentials);
      case HisInOneSessionFailureKind.structureChanged:
        return const GradeFailure(GradeFailureKind.portalStructureChanged);
      case HisInOneSessionFailureKind.timeout:
        return const GradeFailure(GradeFailureKind.timeout);
      case HisInOneSessionFailureKind.networkUnavailable:
        return const GradeFailure(GradeFailureKind.networkUnavailable);
      case HisInOneSessionFailureKind.unknown:
        return const GradeFailure(GradeFailureKind.unknown);
    }
  }
}
