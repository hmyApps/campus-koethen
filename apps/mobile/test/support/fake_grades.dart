// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';

import 'package:campus_koethen/features/grades/domain/clock.dart';
import 'package:campus_koethen/features/grades/domain/exam_report.dart';
import 'package:campus_koethen/features/grades/domain/exam_report_gateway.dart';
import 'package:campus_koethen/features/grades/domain/grade.dart';
import 'package:campus_koethen/features/grades/domain/grade_cache_store.dart';
import 'package:campus_koethen/features/grades/domain/grade_credential_store.dart';
import 'package:campus_koethen/features/grades/domain/grade_credentials.dart';
import 'package:campus_koethen/features/grades/domain/grade_failure.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal_store.dart';
import 'package:campus_koethen/features/grades/domain/grades_gateway.dart';

/// A clock the tests move by hand.
class MutableClock implements Clock {
  MutableClock(this._now);
  DateTime _now;
  void setTo(DateTime value) => _now = value;
  void advance(Duration by) => _now = _now.add(by);
  @override
  DateTime now() => _now;
}

/// In-memory credential store. NEVER touches a platform channel.
class InMemoryGradeCredentialStore implements GradeCredentialStore {
  InMemoryGradeCredentialStore({this.available = true});

  final bool available;
  GradeCredentials? _stored;
  int writes = 0;
  int clears = 0;
  Object? clearError;

  GradeCredentials? get lastWritten => _stored;

  @override
  Future<GradeCredentials?> read() async => _stored;

  @override
  Future<void> write(GradeCredentials credentials) async {
    if (!available) {
      throw const GradeFailure(GradeFailureKind.secureStorageUnavailable);
    }
    _stored = credentials;
    writes++;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (clearError != null) throw clearError!;
    _stored = null;
  }
}

/// In-memory portal store. NEVER touches a platform channel.
class InMemoryGradePortalStore implements GradePortalStore {
  GradePortal? _stored;
  int writes = 0;
  int clears = 0;

  GradePortal? get lastWritten => _stored;

  @override
  Future<GradePortal?> read() async => _stored;

  @override
  Future<void> write(GradePortal portal) async {
    _stored = portal;
    writes++;
  }

  @override
  Future<void> clear() async {
    _stored = null;
    clears++;
  }
}

/// In-memory cache. Records writes so tests can assert the cache is never
/// clobbered by a failed sync.
class InMemoryGradeCacheStore implements GradeCacheStore {
  GradeReport? _report;
  DateTime? _lastSuccess;
  DateTime? _lastAttempt;

  int reportWrites = 0;
  int clears = 0;

  @override
  Future<GradeReport?> readReport() async => _report;

  @override
  Future<void> writeReport(GradeReport report) async {
    _report = report;
    reportWrites++;
  }

  @override
  Future<DateTime?> readLastSuccessfulSync() async => _lastSuccess;

  @override
  Future<void> writeLastSuccessfulSync(DateTime at) async => _lastSuccess = at;

  @override
  Future<DateTime?> readLastAttemptedSync() async => _lastAttempt;

  @override
  Future<void> writeLastAttemptedSync(DateTime at) async => _lastAttempt = at;

  /// When set, [clear] throws instead of wiping — the failed-wipe case that
  /// `deleteEverything` and `switchPortal` used to swallow.
  Object? clearError;

  @override
  Future<void> clear() async {
    clears++;
    if (clearError != null) throw clearError!;
    _report = null;
    _lastSuccess = null;
    _lastAttempt = null;
  }

  /// Whether anything is still stored. Used to assert that a reported wipe
  /// really happened.
  bool get isEmpty =>
      _report == null && _lastSuccess == null && _lastAttempt == null;
}

/// Scriptable gateway. Records how often the portal was hit.
class FakeGradesGateway implements GradesGateway, ExamReportGateway {
  FakeGradesGateway({this.report, this.error, this.delay});

  GradeReport? report;
  GradeFailure? error;

  /// Optional delay so tests can overlap concurrent syncs.
  Duration? delay;

  /// Optional deterministic gate for logout-race tests.
  Completer<GradeReport>? pendingReport;

  int fetchCalls = 0;

  @override
  Future<GradeReport> fetchGrades(GradeCredentials credentials) async {
    fetchCalls++;
    if (pendingReport != null) return pendingReport!.future;
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return report ?? const GradeReport(<GradeEntry>[]);
  }

  /// Scripted answer for `downloadExamReport`.
  ExamReportDownloadResult? examReportResult;
  int downloadExamReportCalls = 0;
  ExamReportOffer? lastRequestedOffer;

  @override
  Future<ExamReportDownloadResult> downloadExamReport(
    GradeCredentials credentials,
    ExamReportOffer offer,
  ) async {
    downloadExamReportCalls++;
    lastRequestedOffer = offer;
    return examReportResult ?? const ExamReportUnavailable('not-scripted');
  }
}

/// A small report for tests.
GradeReport sampleReport([String title = 'Grundlagen']) =>
    GradeReport(<GradeEntry>[
      GradeEntry(
        examNumber: '1',
        title: title,
        grade: const Grade.graded(1.7),
        status: ExamStatus.passed,
        statusText: 'bestanden',
        examDate: DateTime(2026, 2, 12),
      ),
    ]);
