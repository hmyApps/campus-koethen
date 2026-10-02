// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/student_service/domain/student_service_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equality and hashCode compare only the kind, never the stage', () {
    const StudentServiceFailure a = StudentServiceFailure(
      StudentServiceFailureKind.portalStructureChanged,
      stage: 'personalData',
    );
    const StudentServiceFailure b = StudentServiceFailure(
      StudentServiceFailureKind.portalStructureChanged,
      stage: 'contactTiles',
    );
    const StudentServiceFailure c = StudentServiceFailure(
      StudentServiceFailureKind.portalStructureChanged,
    );

    expect(a, b);
    expect(a, c);
    expect(a.hashCode, b.hashCode);
  });

  test('toString includes the stage only when one is set', () {
    const StudentServiceFailure withStage = StudentServiceFailure(
      StudentServiceFailureKind.portalStructureChanged,
      stage: 'tabSwitchResult:report',
    );
    const StudentServiceFailure withoutStage = StudentServiceFailure(
      StudentServiceFailureKind.networkUnavailable,
    );

    expect(
      withStage.toString(),
      'StudentServiceFailure(portalStructureChanged, stage: tabSwitchResult:report)',
    );
    expect(
      withoutStage.toString(),
      'StudentServiceFailure(networkUnavailable)',
    );
  });
}
