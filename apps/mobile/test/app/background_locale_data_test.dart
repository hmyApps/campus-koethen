// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/app/background_sync_entrypoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('a headless run formats dates in both app languages', () async {
    // No widget tree has loaded the date symbols in this isolate, as in a
    // background run: the reminder texts would fail without them.
    expect(() => DateFormat.Hm('de'), throwsA(isA<Object>()));

    await ensureHeadlessLocaleData();

    expect(DateFormat.Hm('de').format(DateTime(2026, 10, 16, 9, 5)), '09:05');
    expect(
      DateFormat.yMMMd('en').format(DateTime(2026, 10, 16)),
      'Oct 16, 2026',
    );
  });
}
