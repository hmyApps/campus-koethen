// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/documents/app_document.dart';
import '../../grades/data/his_in_one_html_parser.dart';
import '../../grades/data/his_in_one_session.dart';
import '../../grades/domain/grade_credentials.dart';
import '../domain/student_service_failure.dart';
import '../domain/student_service_gateway.dart';
import '../domain/student_service_overview.dart';
import '../domain/student_service_profile.dart';
import 'his_in_one_student_service_parser.dart';

/// The "Studienservice" form's own id — also the client id jsf.js adds as
/// its own `id=id` parameter on every AJAX request it builds for a
/// component inside this form (confirmed 2026-10-04 from a real request).
const String _formId = 'studyserviceForm';

/// Tab button ids of the "Studienservice" form, as read from the live
/// portal on 2026-10-01.
abstract final class _Tabs {
  static const String contactData = 'studyserviceForm:newContactData_TabBtn';
  static const String billsAndPayment =
      'studyserviceForm:billsAndPayment_TabBtn';
  static const String report = 'studyserviceForm:report_TabBtn';
}

class HisInOneStudentServiceGateway implements StudentServiceGateway {
  HisInOneStudentServiceGateway([
    this._adapter,
    this._pollInterval = const Duration(seconds: 2),
  ]);

  final HttpClientAdapter? _adapter;
  final Duration _pollInterval;

  @override
  Future<StudentServiceOverview> fetchOverview(
    GradeCredentials credentials,
  ) async {
    final HisInOneSession session = _openSession();
    try {
      await _login(session, credentials);

      // The default tab ("Meine Studiengänge") is what the plain page GET
      // renders — Personendaten and the programme table are read from it.
      final HisInOnePage landing = await session.fetchPage(
        StudentServiceProfile.studyServiceUrl,
      );
      _requireStudyServicePage(landing.html);
      final List<PersonalDataField> personalData =
          HisInOneStudentServiceParser.readPersonalData(landing.html);
      if (personalData.isEmpty ||
          HisInOneStudentServiceParser.hoererstatusOf(personalData) == null) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'personalData',
        );
      }
      final List<ProgrammeEntry>? programmes =
          HisInOneStudentServiceParser.readProgrammes(landing.html);
      if (programmes == null) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'programmes',
        );
      }

      final HisInOnePage contactPage = await _switchTab(
        session,
        landing.html,
        _Tabs.contactData,
      );
      final List<ContactTile> contactTiles =
          HisInOneStudentServiceParser.readContactTiles(contactPage.html);
      if (contactTiles.isEmpty) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'contactTiles',
        );
      }

      final HisInOnePage paymentPage = await _switchTab(
        session,
        contactPage.html,
        _Tabs.billsAndPayment,
      );
      final PaymentHint paymentHint =
          HisInOneStudentServiceParser.readPaymentHint(paymentPage.html);
      if (paymentHint.kind == PaymentHintKind.unrecognised) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'paymentHint',
        );
      }

      final HisInOnePage reportPage = await _switchTab(
        session,
        paymentPage.html,
        _Tabs.report,
      );
      final List<CertificateOffer> certificates =
          HisInOneStudentServiceParser.readCertificateOffers(reportPage.html);
      if (certificates.isEmpty &&
          !HisInOneStudentServiceParser.hasCertificateSection(
            reportPage.html,
          )) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'certificates',
        );
      }

      return StudentServiceOverview(
        personalData: personalData,
        hoererstatus: HisInOneStudentServiceParser.hoererstatusOf(personalData),
        contactTiles: contactTiles,
        programmes: programmes,
        certificates: certificates,
        paymentHint: paymentHint,
        fetchedAt: DateTime.now().toUtc(),
      );
    } on StudentServiceFailure {
      rethrow;
    } on HisInOneSessionFailure catch (e) {
      throw _mapSessionFailure(e);
    } on DioException catch (e) {
      throw _mapSessionFailure(HisInOneSession.mapDioException(e));
    } catch (_) {
      throw const StudentServiceFailure(StudentServiceFailureKind.unknown);
    } finally {
      await session.close(_logoutUrl);
    }
  }

  @override
  Future<CertificateDownloadResult> downloadCertificate(
    GradeCredentials credentials,
    CertificateOffer offer,
  ) async {
    final HisInOneSession session = _openSession();
    try {
      await _login(session, credentials);
      final HisInOnePage landing = await session.fetchPage(
        StudentServiceProfile.studyServiceUrl,
      );
      _requireStudyServicePage(landing.html);
      final HisInOnePage reportPage = await _switchTab(
        session,
        landing.html,
        _Tabs.report,
      );

      // The job button's own id is scoped to THIS render's
      // `_flowExecutionKey` — re-read it fresh rather than trusting the one
      // on the caller's (possibly older) `offer`, and refuse if it no longer
      // matches what is actually on screen now.
      final List<CertificateOffer> current =
          HisInOneStudentServiceParser.readCertificateOffers(reportPage.html);
      final bool stillOffered = current.any(
        (CertificateOffer o) => o.jobButtonId == offer.jobButtonId,
      );
      if (!stillOffered) {
        return const CertificateUnavailable('offer-no-longer-listed');
      }

      final TabSwitchRequest? initialAjaxForm =
          HisInOneStudentServiceParser.buildAjaxFormRequest(reportPage.html);
      if (initialAjaxForm == null) {
        throw const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'ajaxForm',
        );
      }
      TabSwitchRequest ajaxForm = initialAjaxForm;

      // Job generation is a JSF/MyFaces AJAX round trip built from the real
      // page's form/source anchors and the standard partial-response contract.
      // A live account/download token is still part of the manual portal
      // checklist; any unknown response fails closed, never by guessing.
      //
      // All three ids, exactly as the real job button's own onclick handler
      // requests (confirmed 2026-10-04): the overlay that hosts the client
      // poll widget's init marker, the download slot itself, and the
      // message box. Rendering only the download slot — as this used to —
      // never gets back the overlay's poll-init markup at all.
      const String renderTarget =
          'studyserviceForm:report:reports:reportButtons:jobConfigurationButtonsOverlay '
          'studyserviceForm:report:reports:reportButtons:jobDownload '
          'studyserviceForm:messages-infobox';
      // The job button's own onclick calls jsf.ajax.request without an
      // explicit `execute` option, which defaults to `@this` — the clicked
      // component itself, i.e. the same id as `source` here.
      HisInOnePartialResponse started = await _ajaxRequest(
        session,
        ajaxForm,
        sourceId: offer.jobButtonId,
        executeId: offer.jobButtonId,
        renderId: renderTarget,
      );
      String? downloadUrl =
          HisInOneStudentServiceParser.extractDownloadUrlFromPartialResponse(
            started.raw,
          );

      // Not every job starts directly from the button's own AJAX click —
      // confirmed 2026-10-04: "Studienverlaufsbescheinigung" first opens a
      // configuration overlay (asking which semester) instead of starting.
      // Only that overlay's own "PDF erstellen" button — a plain
      // `type="submit"` with no AJAX at all — actually starts the job, via a
      // full page POST/redirect/GET exactly like the grades feature's print
      // buttons. `buildJobConfigurationSubmitRequest` returns `null` when no
      // such overlay is present, which is the normal case for a job that
      // starts right away (e.g. "Gebührenbescheinigung").
      if (downloadUrl == null) {
        final TabSwitchRequest? configSubmit =
            HisInOneStudentServiceParser.buildJobConfigurationSubmitRequest(
              started.raw,
              ajaxForm,
            );
        if (configSubmit != null) {
          final HisInOnePage submitted = await session.postForm(
            configSubmit.action,
            configSubmit.formData,
          );
          downloadUrl =
              HisInOneStudentServiceParser.extractDownloadUrlFromPartialResponse(
                submitted.html,
              );
          // The job may still be generating after the full submit — rebuild
          // the AJAX base from the page actually reached (fresh hidden
          // fields, fresh ViewState) so a subsequent poll targets the right
          // render, same as the already-verified direct-start path.
          final TabSwitchRequest? freshAjaxForm =
              HisInOneStudentServiceParser.buildAjaxFormRequest(submitted.html);
          if (freshAjaxForm != null) {
            ajaxForm = freshAjaxForm;
          }
        }
      }

      if (downloadUrl == null) {
        // The real `<p:poll>` widget's own client id and render target
        // (confirmed 2026-10-04 from a real poll request): a fixed suffix
        // of the same component the job-start step already rendered, not
        // something scraped off a "polling data holder" marker that does
        // not actually exist on the page. Its own onclick explicitly sends
        // `execute:'@none'` — a plain read-only poll tick, never the poll
        // button's own id, which would ask the server to needlessly
        // process/validate it as an input component on every tick.
        for (int attempt = 0; attempt < _maxPollAttempts; attempt++) {
          await Future<void>.delayed(_pollInterval);
          started = await _ajaxRequest(
            session,
            ajaxForm,
            sourceId: '$_pollComponentId:poll',
            executeId: '@none',
            renderId: _pollComponentId,
          );
          downloadUrl =
              HisInOneStudentServiceParser.extractDownloadUrlFromPartialResponse(
                started.raw,
              );
          if (downloadUrl != null) break;
        }
      }
      if (downloadUrl == null) {
        return const CertificateUnavailable('job-not-finished');
      }

      // The real link is site-relative; resolve it against the portal
      // origin before validating/fetching (an already-absolute fallback
      // shape resolves to itself unchanged).
      final String absoluteDownloadUrl = Uri.parse(
        StudentServiceProfile.baseUrl,
      ).resolve(downloadUrl).toString();
      return await _fetchDocument(session, absoluteDownloadUrl, offer.name);
    } on StudentServiceFailure {
      rethrow;
    } on HisInOneSessionFailure catch (e) {
      throw _mapSessionFailure(e);
    } on DioException catch (e) {
      throw _mapSessionFailure(HisInOneSession.mapDioException(e));
    } finally {
      await session.close(_logoutUrl);
    }
  }

  // ---------------------------------------------------------------------

  // 30 attempts × the 2s default interval ≈ 60s total — widened from 10
  // (≈20s) for testing whether the real job just needs more time than that.
  static const int _maxPollAttempts = 30;
  static const String _pollComponentId =
      'studyserviceForm:report:reports:reportButtons:jobDownloadPoll';
  static const String _loginUrl =
      '${StudentServiceProfile.baseUrl}/qisserver/rds'
      '?state=user&type=1&category=auth.login';
  static const String _logoutUrl =
      '${StudentServiceProfile.baseUrl}/qisserver/rds'
      '?state=user&type=3&category=auth.logout';

  HisInOneSession _openSession() => HisInOneSession(
    baseUrl: StudentServiceProfile.baseUrl,
    allows: StudentServiceProfile.allows,
    adapter: _adapter,
  );

  Future<void> _login(HisInOneSession session, GradeCredentials credentials) =>
      session.login(
        loginUrl: _loginUrl,
        username: credentials.username,
        password: credentials.password,
        successSignal: 'category=menu.browse',
        failureSignal: 'hisinoneStartPage.faces',
        isAuthenticated: HisInOneHtmlParser.isAuthenticated,
      );

  void _requireStudyServicePage(String html, {String stage = 'landing'}) {
    if (!HisInOneStudentServiceParser.isStudyServicePage(html)) {
      throw StudentServiceFailure(
        StudentServiceFailureKind.portalStructureChanged,
        stage: stage,
      );
    }
  }

  Future<HisInOnePage> _switchTab(
    HisInOneSession session,
    String currentHtml,
    String tabButtonId,
  ) async {
    final TabSwitchRequest? request =
        HisInOneStudentServiceParser.buildTabSwitchRequest(
          currentHtml,
          tabButtonId,
        );
    if (request == null) {
      throw StudentServiceFailure(
        StudentServiceFailureKind.portalStructureChanged,
        stage: 'tabSwitchRequest:$tabButtonId',
      );
    }
    final HisInOnePage page = await session.postForm(
      request.action,
      request.formData,
    );
    _requireStudyServicePage(page.html, stage: 'tabSwitchResult:$tabButtonId');
    return page;
  }

  /// One JSF/MyFaces partial/ajax request: every hidden field of the current
  /// form, plus the standard `javax.faces.partial.*` markers. Documented
  /// client contract (`jsf.ajax.request`). Start, rotated view-state, polling
  /// and verified PDF download are covered deterministically; a live-account
  /// exchange remains a manual portal check.
  Future<HisInOnePartialResponse> _ajaxRequest(
    HisInOneSession session,
    TabSwitchRequest base, {
    required String sourceId,
    required String renderId,
    required String executeId,
  }) async {
    if (sourceId.isEmpty || renderId.isEmpty || executeId.isEmpty) {
      throw const StudentServiceFailure(
        StudentServiceFailureKind.portalStructureChanged,
        stage: 'ajaxRequestParams',
      );
    }
    // `javax.faces.behavior.event` and `javax.faces.partial.event` are NOT
    // optional bookkeeping: confirmed 2026-10-04 from a real captured job
    // run, omitting them makes the server accept the request (200, a normal
    // partial-response) but never actually run the job — the poll widget's
    // own `data-stop` stays "true" forever and no download link ever
    // appears, the exact failure this was debugging. The real button's own
    // `jsf.ajax.request` call embeds `'javax.faces.behavior.event':'action'`
    // literally in its onclick (both the job button and the poll button);
    // `javax.faces.partial.event` is the real DOM event type jsf.js adds
    // automatically for a genuine click, which a scripted POST has to supply
    // by hand since there is no browser event to read it from.
    final Map<String, String> formData = Map<String, String>.of(base.formData)
      ..addAll(<String, String>{
        'javax.faces.partial.ajax': 'true',
        'javax.faces.source': sourceId,
        'javax.faces.partial.execute': executeId,
        'javax.faces.partial.render': renderId,
        'javax.faces.behavior.event': 'action',
        'javax.faces.partial.event': 'click',
        // jsf.js's own ajax request always adds the enclosing form's own
        // id=id pair on top of the form's hidden fields — also confirmed
        // 2026-10-04 from the real request body.
        _formId: _formId,
      });
    final HisInOnePage raw = await session.postForm(base.action, formData);
    final String? nextViewState =
        HisInOneStudentServiceParser.viewStateFromPartialResponse(raw.html);
    if (nextViewState != null) {
      base.formData['javax.faces.ViewState'] = nextViewState;
    }
    return HisInOnePartialResponse(raw: raw.html, html: raw.html);
  }

  Future<CertificateDownloadResult> _fetchDocument(
    HisInOneSession session,
    String url,
    String fallbackName,
  ) async {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException {
      return const CertificateUnavailable('invalid-url');
    }
    if (!StudentServiceProfile.allowsDocumentDownload(uri)) {
      return const CertificateUnavailable('host-rejected');
    }
    try {
      final Response<ResponseBody> response = await session.fetchStream(
        uri.toString(),
        allowsTarget: StudentServiceProfile.allowsDocumentDownload,
      );
      if ((response.statusCode ?? 0) != 200) {
        return CertificateUnavailable('http-${response.statusCode}');
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
        return const CertificateUnavailable('not-a-pdf');
      }
      final int? declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null && declaredLength > kMaxInMemoryPreviewBytes) {
        return const CertificateTooLarge();
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      final ResponseBody? body = response.data;
      if (body == null) return const CertificateUnavailable('empty-body');
      await for (final Uint8List chunk in body.stream) {
        if (builder.length + chunk.length > kMaxInMemoryPreviewBytes) {
          return const CertificateTooLarge();
        }
        builder.add(chunk);
      }
      final Uint8List bytes = builder.takeBytes();
      if (bytes.isEmpty) return const CertificateUnavailable('empty-body');
      if (!_hasPdfMagic(bytes)) {
        return const CertificateUnavailable('not-a-pdf');
      }
      return CertificateDownloadLoaded(
        bytes: bytes,
        filename: safeDocumentFilename('$fallbackName.pdf'),
      );
    } on DioException catch (e) {
      return CertificateUnavailable('dio-${e.type.name}');
    }
  }

  static bool _hasPdfMagic(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2d;

  static StudentServiceFailure _mapSessionFailure(HisInOneSessionFailure e) {
    switch (e.kind) {
      case HisInOneSessionFailureKind.hostRejected:
        return const StudentServiceFailure(
          StudentServiceFailureKind.tlsOrHostRejected,
        );
      case HisInOneSessionFailureKind.unavailable:
        return const StudentServiceFailure(
          StudentServiceFailureKind.portalUnavailable,
        );
      case HisInOneSessionFailureKind.loginRejected:
        return const StudentServiceFailure(
          StudentServiceFailureKind.invalidCredentials,
        );
      case HisInOneSessionFailureKind.structureChanged:
        return const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'session',
        );
      case HisInOneSessionFailureKind.timeout:
        return const StudentServiceFailure(StudentServiceFailureKind.timeout);
      case HisInOneSessionFailureKind.networkUnavailable:
        return const StudentServiceFailure(
          StudentServiceFailureKind.networkUnavailable,
        );
      case HisInOneSessionFailureKind.unknown:
        return const StudentServiceFailure(StudentServiceFailureKind.unknown);
    }
  }
}

/// One JSF partial-response. [raw] is the exact response body, scanned for a
/// download link; [html] is the same body, scanned by the DOM parser for the
/// poll marker — both views of one response, kept separate only because the
/// two extractions look for different shapes.
class HisInOnePartialResponse {
  const HisInOnePartialResponse({required this.raw, required this.html});
  final String raw;
  final String html;
}
