// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/cache/encrypted_box.dart';
import 'package:campus_koethen/features/student_service/data/encrypted_student_service_cache.dart';
import 'package:campus_koethen/features/student_service/domain/student_service_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clear rejects an incomplete encrypted wipe', () async {
    final EncryptedStudentServiceCache cache = EncryptedStudentServiceCache(
      _WipeBox(const EncryptedBoxWipeResult(keyAbsent: false, boxAbsent: true)),
    );

    await expectLater(
      cache.clear(),
      throwsA(
        const StudentServiceFailure(StudentServiceFailureKind.cacheUnavailable),
      ),
    );
  });

  test('clear succeeds once both the key and the box are gone', () async {
    final EncryptedStudentServiceCache cache = EncryptedStudentServiceCache(
      _WipeBox(const EncryptedBoxWipeResult(keyAbsent: true, boxAbsent: true)),
    );

    await expectLater(cache.clear(), completes);
  });

  test('a failed read never throws — it is treated as no cache', () async {
    final EncryptedStudentServiceCache cache = EncryptedStudentServiceCache(
      _UnreadableBox(),
    );

    expect(await cache.readOverview(), isNull);
  });
}

class _WipeBox extends EncryptedBox {
  _WipeBox(this.result) : super(boxName: 'unused', keyStorageKey: 'unused-key');

  final EncryptedBoxWipeResult result;

  @override
  Future<EncryptedBoxWipeResult> wipeChecked() async => result;
}

/// Simulates a stored value that is present but no longer decodable as the
/// expected JSON shape — a corrupt or format-shifted entry, not a parse
/// crash that should propagate.
class _UnreadableBox extends EncryptedBox {
  _UnreadableBox() : super(boxName: 'unused', keyStorageKey: 'unused-key');

  @override
  Future<String?> read(String key) async =>
      key == 'overview' ? 'not-json-at-all' : null;
}
