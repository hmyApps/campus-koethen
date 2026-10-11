// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/chat/data/sdk_matrix_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(resetVodozemacLoadForTest);
  tearDown(resetVodozemacLoadForTest);

  test('loads the native library once, however many gateways ask', () async {
    var loads = 0;
    Future<void> load() async => loads++;

    await loadOncePerProcess(load);
    await loadOncePerProcess(load);
    await Future.wait(<Future<void>>[
      loadOncePerProcess(load),
      loadOncePerProcess(load),
    ]);

    expect(loads, 1);
  });

  test('a failed load is tried again next time', () async {
    var attempts = 0;
    Future<void> load() async {
      attempts++;
      if (attempts == 1) throw StateError('library missing');
    }

    await expectLater(loadOncePerProcess(load), throwsStateError);
    await loadOncePerProcess(load);

    expect(attempts, 2);
  });
}
