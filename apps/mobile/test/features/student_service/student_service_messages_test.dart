// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/student_service/domain/student_service_failure.dart';
import 'package:campus_koethen/features/student_service/presentation/student_service_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('surfaces the stage only for a portal-structure mismatch', () {
    expect(
      studentServiceDiagnosticStage(
        const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
          stage: 'personalData',
        ),
      ),
      'personalData',
    );
    expect(
      studentServiceDiagnosticStage(
        const StudentServiceFailure(StudentServiceFailureKind.timeout),
      ),
      isNull,
    );
    expect(
      studentServiceDiagnosticStage(
        const StudentServiceFailure(
          StudentServiceFailureKind.portalStructureChanged,
        ),
      ),
      isNull,
    );
    expect(studentServiceDiagnosticStage(null), isNull);
  });
}
