// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/moodle_account.dart';
import '../domain/moodle_announcement.dart';
import '../domain/moodle_api_client.dart';
import '../domain/moodle_assignment.dart';
import '../domain/moodle_content.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_deadline.dart';
import '../domain/moodle_failure.dart';
import '../domain/moodle_profile.dart';
import 'moodle_parsers.dart';

/// Transport limits shared by every request to Moodle, file downloads included.
const Duration kMoodleConnectTimeout = Duration(seconds: 20);
const Duration kMoodleSendTimeout = Duration(seconds: 20);

/// The longest silence tolerated while waiting for a response — or, for a
/// streamed download, for its next chunk. Dio treats it as an idle timeout.
const Duration kMoodleReceiveTimeout = Duration(seconds: 30);

/// The one component that talks to Moodle over the network.
///
/// The security policy here is central and non-bypassable:
///  * every request goes only to HTTPS on `moodle.hs-anhalt.de` — enforced with
///    [MoodleProfile.allows] before the request leaves;
///  * the token travels in the POST body, never in a query string;
///  * redirects are never followed — a 3xx (which could point at another host)
///    is refused so the token can never be replayed elsewhere;
///  * Moodle errors delivered as HTTP 200 with an `exception` envelope are
///    detected and mapped to a classified failure;
///  * no token, password, full URL or full response body ever reaches a thrown
///    error — only a [MoodleFailure] classification.
class MoodleHttpClient implements MoodleApiClient {
  MoodleHttpClient({Dio? dio, this.profile = const MoodleProfile()})
    : _dio = dio ?? _defaultDio();

  final Dio _dio;
  final MoodleProfile profile;

  static Dio _defaultDio() {
    return Dio(
      BaseOptions(
        // Everything is handled manually so the token can never be replayed to
        // a redirect target and non-2xx never throws before we classify it.
        followRedirects: false,
        validateStatus: (_) => true,
        connectTimeout: kMoodleConnectTimeout,
        receiveTimeout: kMoodleReceiveTimeout,
        sendTimeout: kMoodleSendTimeout,
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<String> requestToken({
    required String username,
    required String password,
  }) async {
    final Object? json = await _postForm(profile.tokenUrl, <String, String>{
      'username': username,
      'password': password,
      'service': profile.service,
    });
    return parseToken(json);
  }

  @override
  Future<MoodleSiteInfo> getSiteInfo(String token) async {
    final Object? json = await _rest(token, 'core_webservice_get_site_info');
    return parseSiteInfo(json);
  }

  @override
  Future<List<MoodleCourse>> getCourses({required String token}) async {
    final Object? json = await _rest(
      token,
      'core_course_get_enrolled_courses_by_timeline_classification',
      <String, String>{'classification': 'inprogress'},
    );
    return parseCourses(json);
  }

  @override
  Future<List<MoodleSection>> getCourseContents({
    required String token,
    required int courseId,
  }) async {
    final Object? json = await _rest(
      token,
      'core_course_get_contents',
      <String, String>{'courseid': '$courseId'},
    );
    return parseSections(json);
  }

  @override
  Future<List<MoodleAssignment>> getAssignments({
    required String token,
    required List<int> courseIds,
  }) async {
    final Map<String, String> params = <String, String>{};
    for (int i = 0; i < courseIds.length; i++) {
      params['courseids[$i]'] = '${courseIds[i]}';
    }
    final Object? json = await _rest(
      token,
      'mod_assign_get_assignments',
      params,
    );
    return parseAssignments(json);
  }

  @override
  Future<MoodleSubmissionStatus> getSubmissionStatus({
    required String token,
    required int assignmentId,
  }) async {
    final Object? json = await _rest(
      token,
      'mod_assign_get_submission_status',
      <String, String>{'assignid': '$assignmentId'},
    );
    return parseSubmissionStatus(json);
  }

  @override
  Future<List<MoodleAnnouncement>> getAnnouncements({
    required String token,
    required int courseId,
  }) async {
    final Object? forumsJson = await _rest(
      token,
      'mod_forum_get_forums_by_courses',
      <String, String>{'courseids[0]': '$courseId'},
    );
    final List<int> newsForumIds = parseNewsForumIds(forumsJson);
    final List<MoodleAnnouncement> out = <MoodleAnnouncement>[];
    for (final int forumId in newsForumIds) {
      final Object? discussionsJson = await _rest(
        token,
        'mod_forum_get_forum_discussions',
        <String, String>{'forumid': '$forumId'},
      );
      out.addAll(parseDiscussions(discussionsJson, courseId: courseId));
    }
    return out;
  }

  @override
  Future<List<MoodleDeadline>> getUpcomingDeadlines({
    required String token,
    DateTime? from,
    int limit = 50,
  }) async {
    final int fromSeconds =
        (from ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final Object? json = await _rest(
      token,
      'core_calendar_get_action_events_by_timesort',
      <String, String>{
        'timesortfrom': '$fromSeconds',
        'limitnum': '$limit',
        'limittononsuspendedevents': '1',
      },
    );
    return parseDeadlines(json);
  }

  // -------------------------------------------------------------------------
  // Transport
  // -------------------------------------------------------------------------

  Future<Object?> _rest(
    String token,
    String wsFunction, [
    Map<String, String> params = const <String, String>{},
  ]) {
    final Map<String, String> body = <String, String>{
      'wstoken': token,
      'wsfunction': wsFunction,
      'moodlewsrestformat': 'json',
      ...params,
    };
    return _postForm(profile.restUrl, body);
  }

  Future<Object?> _postForm(String url, Map<String, String> body) async {
    final Uri uri = Uri.parse(url);
    // Defence in depth: never send anything anywhere but the pinned host.
    if (!profile.allows(uri)) {
      throw const MoodleFailure(MoodleFailureKind.tlsOrHostRejected);
    }

    late final Response<dynamic> response;
    try {
      response = await _dio.postUri<dynamic>(
        uri,
        data: body,
        // The policy is pinned per-request so it holds even if the injected
        // Dio was built without our base options: never auto-follow a redirect
        // (it could carry the token to another host) and classify every status
        // ourselves instead of letting Dio throw first.
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }

    final int status = response.statusCode ?? 0;

    // A redirect could point at another host — never follow it with the token.
    if (status >= 300 && status < 400) {
      throw const MoodleFailure(MoodleFailureKind.tlsOrHostRejected);
    }
    if (status == 401 || status == 403) {
      throw const MoodleFailure(MoodleFailureKind.permissionDenied);
    }
    if (status >= 500) {
      throw const MoodleFailure(MoodleFailureKind.serviceUnavailable);
    }
    if (status < 200 || status >= 300) {
      throw const MoodleFailure(MoodleFailureKind.invalidResponse);
    }

    final Object? json = _decode(response.data);
    // Moodle delivers many errors as HTTP 200 with an exception envelope.
    final MoodleFailure? exception = moodleExceptionOf(json);
    if (exception != null) throw exception;
    return json;
  }

  Object? _decode(Object? data) {
    // Every whitelisted function answers with a JSON structure. A missing or
    // blank 200 body is therefore a broken answer, never an empty result —
    // reading it as one let it replace good cached data (AGENTS §4).
    if (data == null) {
      throw const MoodleFailure(MoodleFailureKind.invalidResponse);
    }
    if (data is String) {
      if (data.trim().isEmpty) {
        throw const MoodleFailure(MoodleFailureKind.invalidResponse);
      }
      try {
        return jsonDecode(data);
      } on FormatException {
        throw const MoodleFailure(MoodleFailureKind.invalidResponse);
      }
    }
    // Already-decoded structures (defensive).
    return data;
  }

  MoodleFailure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const MoodleFailure(MoodleFailureKind.timeout);
      case DioExceptionType.badCertificate:
        return const MoodleFailure(MoodleFailureKind.tlsOrHostRejected);
      case DioExceptionType.connectionError:
        return const MoodleFailure(MoodleFailureKind.networkUnavailable);
      case DioExceptionType.cancel:
        return const MoodleFailure(MoodleFailureKind.downloadFailed);
      case DioExceptionType.badResponse:
        return const MoodleFailure(MoodleFailureKind.invalidResponse);
      case DioExceptionType.unknown:
        return const MoodleFailure(MoodleFailureKind.networkUnavailable);
    }
  }
}
