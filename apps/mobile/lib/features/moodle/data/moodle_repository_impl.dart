// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../core/documents/app_document.dart';
import '../../../core/security/session_guard.dart';
import '../../../core/time/clock.dart';
import '../domain/moodle_account.dart';
import '../domain/moodle_announcement.dart';
import '../domain/moodle_api_client.dart';
import '../domain/moodle_assignment.dart';
import '../domain/moodle_cache.dart';
import '../domain/moodle_content.dart';
import '../domain/moodle_course.dart';
import '../domain/moodle_deadline.dart';
import '../domain/moodle_downloader.dart';
import '../domain/moodle_failure.dart';
import '../domain/moodle_repository.dart';
import 'moodle_file_downloader.dart';

/// The one component that ever holds a live Moodle token.
///
/// It composes the API client, the encrypted cache and the secure token store,
/// and it guarantees the core data-integrity rule: a degraded response never
/// destroys the last good cache. A failed fetch throws before any write. An
/// empty in-progress course list is authoritative and clears courses that
/// Moodle no longer considers current; an empty deadline list still keeps a
/// previously populated deadline cache.
class MoodleRepositoryImpl implements MoodleRepository {
  MoodleRepositoryImpl({
    required MoodleApiClient apiClient,
    required MoodleTokenStore tokenStore,
    required MoodleCacheStore cacheStore,
    MoodleFileDownloader? fileDownloader,
    Clock clock = const SystemClock(),
    SessionGuard<int>? sessionGuard,
  }) : _api = apiClient,
       _tokens = tokenStore,
       _cache = cacheStore,
       _downloader = fileDownloader ?? MoodleFileDownloaderImpl(),
       // A private field cannot be a named initializing formal, and the public
       // API keeps `clock:`.
       // ignore: prefer_initializing_formals
       _clock = clock,
       _sessions = sessionGuard;

  final MoodleApiClient _api;
  final MoodleTokenStore _tokens;
  final MoodleCacheStore _cache;
  final MoodleFileDownloader _downloader;
  final Clock _clock;
  final SessionGuard<int>? _sessions;

  @override
  Future<MoodleAccount?> currentAccount() async {
    final MoodleToken? token = await _tokens.read();
    if (token == null) {
      await _sessions?.invalidateAndWait();
    } else {
      _sessions?.initializeIfNeeded(token.userId);
    }
    return token?.toAccount();
  }

  @override
  Future<MoodleAccount> connect({
    required String username,
    required String password,
  }) async {
    // 1. Exchange credentials for a token.
    final String tokenValue = await _api.requestToken(
      username: username,
      password: password,
    );
    // 2. Verify the token BEFORE storing anything.
    final MoodleSiteInfo info = await _api.getSiteInfo(tokenValue);
    // 3. Only now persist — the password itself is never stored.
    final MoodleToken token = MoodleToken(
      value: tokenValue,
      userId: info.userId,
      username: info.username ?? username,
      siteName: info.siteName,
    );
    await _sessions?.invalidateAndWait();
    await _tokens.write(token);
    _sessions?.activate(token.userId);
    return token.toAccount();
  }

  @override
  Future<void> disconnect() async {
    // Invalidate before deletion and wait until every tracked writer has
    // observed it. The verified wipe therefore runs after the final possible
    // cache write, never before it.
    await _sessions?.invalidateAndWait();

    MoodleFailure? failure;
    try {
      await _tokens.clear();
    } catch (error) {
      failure ??= error is MoodleFailure
          ? error
          : const MoodleFailure(MoodleFailureKind.secureStorageUnavailable);
    }
    try {
      await _cache.clear();
    } catch (error) {
      failure ??= error is MoodleFailure
          ? error
          : const MoodleFailure(MoodleFailureKind.cacheUnavailable);
    }
    if (failure != null) throw failure;
  }

  @override
  Future<List<MoodleCourse>?> cachedCourses() => _cache.readCourses();

  @override
  Future<List<MoodleDeadline>?> cachedDeadlines() => _cache.readDeadlines();

  @override
  Future<MoodleSyncMarks> syncMarks() => _cache.readMarks();

  @override
  Future<void> recordAttempt(DateTime at) async {
    await _withActiveSession<void>((
      MoodleToken token,
      SessionLease<int>? lease,
    ) async {
      final MoodleSyncMarks marks = await _cache.readMarks();
      _ensureCurrent(lease);
      await _cache.writeMarks(marks.copyWith(lastAttempt: at));
      _ensureCurrent(lease);
    });
  }

  @override
  Future<MoodleOverview> refreshOverview() =>
      _withActiveSession<MoodleOverview>(_refreshOverview);

  Future<MoodleOverview> _refreshOverview(
    MoodleToken token,
    SessionLease<int>? lease,
  ) async {
    // Courses and deadlines are two independent Moodle calls, and the deadline
    // cache read that guards an empty deadline response depends on neither. Run
    // in turn they cost three latencies where one suffices. A failure in any of
    // them still aborts the whole refresh before a single write, exactly as
    // before.
    //
    // `Future.wait` rather than the record `.wait`: the record form reports a
    // failure as a `ParallelWaitError`, which would strip the `MoodleFailure`
    // classification the controller relies on to tell an expired token from an
    // unknown error. `Future.wait` rethrows the original error object.
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _api.getCourses(token: token.value),
      _api.getUpcomingDeadlines(token: token.value),
      // Data-integrity guard for the deadline feed. The in-progress course
      // response is authoritative even when it is empty.
      _cache.readDeadlines(),
    ]);
    _ensureCurrent(lease);
    final List<MoodleCourse> fetchedCourses = results[0]! as List<MoodleCourse>;
    final List<MoodleDeadline> fetchedDeadlines =
        results[1]! as List<MoodleDeadline>;
    final List<MoodleDeadline>? oldDeadlines =
        results[2] as List<MoodleDeadline>?;

    // Unlike the old unclassified enrolment list, an empty `inprogress`
    // response is meaningful: the user currently has no active courses. It
    // must replace stale cached courses so the app stays aligned with Moodle
    // Web. Structurally invalid and failed responses throw before this point.
    final List<MoodleCourse> effectiveCourses = fetchedCourses;
    final List<MoodleDeadline> effectiveDeadlines = _keepIfEmpty(
      fetchedDeadlines,
      oldDeadlines,
    );

    _ensureCurrent(lease);
    await _cache.writeCourses(effectiveCourses);
    _ensureCurrent(lease);
    await _cache.writeDeadlines(effectiveDeadlines);
    _ensureCurrent(lease);

    final DateTime now = _clock.now();
    final MoodleSyncMarks marks = await _cache.readMarks();
    _ensureCurrent(lease);
    await _cache.writeMarks(marks.copyWith(lastAttempt: now, lastSuccess: now));
    _ensureCurrent(lease);

    return MoodleOverview(
      courses: effectiveCourses,
      deadlines: effectiveDeadlines,
    );
  }

  @override
  Future<MoodleCourseDetail?> cachedCourseDetail(int courseId) async {
    final MoodleCourse? course = await _findCachedCourse(courseId);
    if (course == null) return null;
    final List<MoodleSection>? sections = await _cache.readSections(courseId);
    if (sections == null) return null; // never loaded
    return MoodleCourseDetail(
      course: course,
      sections: sections,
      assignments:
          await _cache.readAssignments(courseId) ?? const <MoodleAssignment>[],
      announcements:
          await _cache.readAnnouncements(courseId) ??
          const <MoodleAnnouncement>[],
      fetchedAt: await _cache.readCourseDetailFetchedAt(courseId),
    );
  }

  @override
  Future<MoodleCourseDetail> refreshCourseDetail(int courseId) =>
      _withActiveSession<MoodleCourseDetail>(
        (MoodleToken token, SessionLease<int>? lease) =>
            _refreshCourseDetail(courseId, token, lease),
      );

  Future<MoodleCourseDetail> _refreshCourseDetail(
    int courseId,
    MoodleToken token,
    SessionLease<int>? lease,
  ) async {
    final MoodleCourse course =
        await _findCachedCourse(courseId) ??
        // Deliberately empty rather than a hardcoded German "Kurs 12": the
        // presentation layer localises the fallback (see
        // `moodleCourseFallbackName`). A data layer has no business holding
        // user-visible copy in one language.
        MoodleCourse(id: courseId, fullName: '');
    _ensureCurrent(lease);

    // Contents, assignments and announcements are three independent calls; only
    // the submission statuses below genuinely depend on one of them. Opening a
    // course used to pay for all three latencies in a row. Same `Future.wait`
    // reasoning as `refreshOverview`: the original `MoodleFailure` must survive.
    final List<Object?> parts = await Future.wait<Object?>(<Future<Object?>>[
      _api.getCourseContents(token: token.value, courseId: courseId),
      _api.getAssignments(token: token.value, courseIds: <int>[courseId]),
      _api.getAnnouncements(token: token.value, courseId: courseId),
    ]);
    _ensureCurrent(lease);
    final List<MoodleSection> sections = parts[0]! as List<MoodleSection>;
    final List<MoodleAssignment> assignments =
        parts[1]! as List<MoodleAssignment>;
    final List<MoodleAnnouncement> announcements =
        parts[2]! as List<MoodleAnnouncement>;

    final List<MoodleSubmissionStatus> statuses = await _submissionStatuses(
      token: token,
      assignments: assignments,
      lease: lease,
    );
    _ensureCurrent(lease);
    final List<MoodleAssignment> withStatus = <MoodleAssignment>[
      for (int i = 0; i < assignments.length; i++)
        assignments[i].withStatus(_flagLate(assignments[i], statuses[i])),
    ];

    _ensureCurrent(lease);
    await _cache.writeSections(courseId, sections);
    _ensureCurrent(lease);
    await _cache.writeAssignments(courseId, withStatus);
    _ensureCurrent(lease);
    await _cache.writeAnnouncements(courseId, announcements);
    _ensureCurrent(lease);
    final DateTime fetchedAt = _clock.now();
    await _cache.writeCourseDetailFetchedAt(courseId, fetchedAt);
    _ensureCurrent(lease);

    return MoodleCourseDetail(
      course: course,
      sections: sections,
      assignments: withStatus,
      announcements: announcements,
      fetchedAt: fetchedAt,
    );
  }

  @override
  Future<AppDocument> downloadFile(
    MoodleFile file, {
    MoodleDownloadProgress? onProgress,
    MoodleDownloadCancel? cancel,
  }) async {
    final MoodleToken token = await _requireToken();
    return _downloader.download(
      token: token.value,
      fileUrl: file.fileUrl,
      fileName: file.fileName,
      declaredMimeType: file.mimeType,
      declaredSize: file.fileSize,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  // -------------------------------------------------------------------------

  Future<MoodleToken> _requireToken() async {
    final MoodleToken? token = await _tokens.read();
    if (token == null) {
      throw const MoodleFailure(MoodleFailureKind.tokenExpired);
    }
    return token;
  }

  Future<T> _withActiveSession<T>(
    Future<T> Function(MoodleToken token, SessionLease<int>? lease) operation,
  ) async {
    final MoodleToken token = await _requireToken();
    final SessionGuard<int>? sessions = _sessions;
    if (sessions == null) return operation(token, null);

    sessions.initializeIfNeeded(token.userId);
    final SessionLease<int>? lease = sessions.capture(token.userId);
    if (lease == null) throw const SessionInvalidated();
    return sessions.track<T>(lease, () => operation(token, lease));
  }

  void _ensureCurrent(SessionLease<int>? lease) {
    if (lease != null && !(_sessions?.isCurrent(lease) ?? false)) {
      throw const SessionInvalidated();
    }
  }

  Future<MoodleCourse?> _findCachedCourse(int courseId) async {
    final List<MoodleCourse>? courses = await _cache.readCourses();
    if (courses == null) return null;
    for (final MoodleCourse c in courses) {
      if (c.id == courseId) return c;
    }
    return null;
  }

  /// Returns [fresh] unless it is empty while [old] holds good data — in which
  /// case the good data is kept (an empty response must not wipe the cache).
  List<T> _keepIfEmpty<T>(List<T> fresh, List<T>? old) {
    if (fresh.isEmpty && old != null && old.isNotEmpty) return old;
    return fresh;
  }

  /// Fetches one submission status per assignment, tolerating failures and
  /// keeping the request count bounded.
  ///
  /// Two problems with the plain `Future.wait` this replaces. It is fail-fast,
  /// so a single 403 or timeout on one assignment threw away the whole course
  /// page — contents and announcements already fetched and perfectly good. And
  /// it opened one request per assignment at once, which on a course with
  /// twenty-odd assignments meant twenty-odd simultaneous calls into the
  /// university's Moodle.
  ///
  /// An assignment whose status cannot be read falls back to
  /// [MoodleSubmissionState.unknown], which the UI already renders as a
  /// "status unknown" chip — an honest gap in one row rather than an error
  /// page over everything.
  Future<List<MoodleSubmissionStatus>> _submissionStatuses({
    required MoodleToken token,
    required List<MoodleAssignment> assignments,
    SessionLease<int>? lease,
  }) async {
    final List<MoodleSubmissionStatus> statuses =
        List<MoodleSubmissionStatus>.filled(
          assignments.length,
          const MoodleSubmissionStatus(),
        );
    for (int start = 0; start < assignments.length; start += _statusBatchSize) {
      final int end = (start + _statusBatchSize) < assignments.length
          ? start + _statusBatchSize
          : assignments.length;
      final List<MoodleSubmissionStatus?> batch =
          await Future.wait<MoodleSubmissionStatus?>(
            <Future<MoodleSubmissionStatus?>>[
              for (int i = start; i < end; i++)
                _api
                    .getSubmissionStatus(
                      token: token.value,
                      assignmentId: assignments[i].id,
                    )
                    .then<MoodleSubmissionStatus?>(
                      (MoodleSubmissionStatus status) => status,
                    )
                    // One unreadable status is a gap in one row, never a failed
                    // course page.
                    .catchError((Object _) => null),
            ],
          );
      _ensureCurrent(lease);
      for (int i = start; i < end; i++) {
        statuses[i] = batch[i - start] ?? const MoodleSubmissionStatus();
      }
    }
    return statuses;
  }

  /// How many submission-status calls may be in flight at once.
  ///
  /// Small on purpose: these all go to one university Moodle, and a course
  /// with two dozen assignments used to open two dozen simultaneous requests.
  static const int _statusBatchSize = 4;

  MoodleSubmissionStatus _flagLate(
    MoodleAssignment assignment,
    MoodleSubmissionStatus status,
  ) {
    final DateTime? due = assignment.dueDate;
    final DateTime? submitted = status.submittedAt;
    final bool late =
        due != null && submitted != null && submitted.isAfter(due);
    return late ? status.copyWith(isLate: true) : status;
  }
}
