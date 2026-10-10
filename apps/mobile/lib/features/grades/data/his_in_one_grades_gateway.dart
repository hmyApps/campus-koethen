// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/documents/app_document.dart';
import '../domain/exam_report.dart';
import '../domain/exam_report_gateway.dart';
import '../domain/grade.dart';
import '../domain/grade_credentials.dart';
import '../domain/grade_failure.dart';
import '../domain/grades_gateway.dart';
import '../domain/his_in_one_profile.dart';
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
class HisInOneGradesGateway implements GradesGateway, ExamReportGateway {
  HisInOneGradesGateway(this._profile, [this._adapter]);

  final HisInOneProfile _profile;
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
          // The "Bescheinigungen" print buttons, if any, live on this SAME
          // page — read them from the one fetch already in hand rather
          // than fetching the page again.
          return await _withExamReports(overview.html);
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
      return await _withExamReports(expanded.html);
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

  Future<GradeReport> _withExamReports(String html) async {
    final GradeReport report = await HisInOneHtmlParser.parseGradeReport(html);
    final List<ExamReportOffer> offers =
        await HisInOneHtmlParser.findExamReports(html);
    return GradeReport(report.entries, examReports: offers);
  }

  @override
  Future<ExamReportDownloadResult> downloadExamReport(
    GradeCredentials credentials,
    ExamReportOffer offer,
  ) async {
    final HisInOneSession session = HisInOneSession(
      baseUrl: _profile.baseUrl,
      allows: _profile.allows,
      adapter: _adapter,
    );
    try {
      await session.login(
        loginUrl: _profile.loginUrl,
        username: credentials.username,
        password: credentials.password,
        successSignal: 'category=menu.browse',
        failureSignal: 'hisinoneStartPage.faces',
        isAuthenticated: HisInOneHtmlParser.isAuthenticated,
      );
      final HisInOnePage overview = await session.fetchPage(_examOverviewUrl());

      // The button's own id is scoped to THIS render's `_flowExecutionKey`
      // — re-read it fresh rather than trusting the caller's (possibly
      // older) offer, and refuse if it no longer matches what is actually
      // on screen now.
      final List<ExamReportOffer> current =
          await HisInOneHtmlParser.findExamReports(overview.html);
      final bool stillOffered = current.any(
        (ExamReportOffer o) => o.buttonId == offer.buttonId,
      );
      if (!stillOffered) {
        return const ExamReportUnavailable('offer-no-longer-listed');
      }

      final HisInOneFullPostRequest? request =
          await HisInOneHtmlParser.buildExamReportPostRequest(
            overview.html,
            offer.buttonId,
          );
      if (request == null) {
        throw const GradeFailure(GradeFailureKind.portalStructureChanged);
      }

      return await _fetchReportDocument(session, request, offer.label);
    } on GradeFailure {
      rethrow;
    } on HisInOneSessionFailure catch (e) {
      throw _mapSessionFailure(e);
    } on DioException catch (e) {
      throw _mapSessionFailure(HisInOneSession.mapDioException(e));
    } catch (_) {
      throw const GradeFailure(GradeFailureKind.unknown);
    } finally {
      await session.close(_profile.logoutUrl);
    }
  }

  /// Submits the full-POST [request] and streams the result through every
  /// same-host redirect hop (the real portal's one-time download, confirmed
  /// 2026-10-04) — the same verified-document contract as
  /// `HisInOneStudentServiceGateway._fetchDocument`: exact content-type,
  /// a size budget enforced while streaming (never after fully buffering),
  /// and a real PDF-magic check on the bytes that actually arrived.
  Future<ExamReportDownloadResult> _fetchReportDocument(
    HisInOneSession session,
    HisInOneFullPostRequest request,
    String fallbackName,
  ) async {
    final Response<ResponseBody> response = await session.postFormStream(
      request.action,
      request.formData,
      allowsTarget: _profile.examReportDownloadRoute(),
    );
    if ((response.statusCode ?? 0) != 200) {
      return ExamReportUnavailable('http-${response.statusCode}');
    }
    final String mediaType =
        response.headers
            .value(Headers.contentTypeHeader)
            ?.split(';')
            .first
            .trim()
            .toLowerCase() ??
        '';
    if (mediaType.isNotEmpty &&
        mediaType != 'application/pdf' &&
        mediaType != 'application/octet-stream') {
      return const ExamReportUnavailable('not-a-pdf');
    }
    final int? declaredLength = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (declaredLength != null && declaredLength > kMaxInMemoryPreviewBytes) {
      return const ExamReportTooLarge();
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    final ResponseBody? body = response.data;
    if (body == null) return const ExamReportUnavailable('empty-body');
    await for (final Uint8List chunk in body.stream) {
      if (builder.length + chunk.length > kMaxInMemoryPreviewBytes) {
        return const ExamReportTooLarge();
      }
      builder.add(chunk);
    }
    final Uint8List bytes = builder.takeBytes();
    if (bytes.isEmpty) return const ExamReportUnavailable('empty-body');
    if (!_hasPdfMagic(bytes)) {
      return const ExamReportUnavailable('not-a-pdf');
    }
    return ExamReportDownloadLoaded(
      bytes: bytes,
      filename: safeDocumentFilename('$fallbackName.pdf'),
    );
  }

  static bool _hasPdfMagic(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2d;

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
