// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/canteen/domain/canteen_balance_apdu.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/canteen_balance_responses.dart';

void main() {
  test('uses only the two validated read-only APDUs', () {
    expect(CanteenBalanceApdu.selectApplication, <int>[
      0x90,
      0x5a,
      0x00,
      0x00,
      0x03,
      0x5f,
      0x84,
      0x15,
      0x00,
    ]);
    expect(CanteenBalanceApdu.readBalance, <int>[
      0x90,
      0x6c,
      0x00,
      0x00,
      0x01,
      0x01,
      0x00,
    ]);
  });

  test('accepts the exact DESFire success response for app selection', () {
    expect(
      () => CanteenBalanceApdu.validateSelection(
        CanteenBalanceResponses.selected,
      ),
      returnsNormally,
    );
  });

  test('parses signed Int32 little endian without floating point', () {
    final CanteenBalance positive = CanteenBalanceApdu.parseBalance(
      CanteenBalanceResponses.positive,
    );
    final CanteenBalance negative = CanteenBalanceApdu.parseBalance(
      CanteenBalanceResponses.negative,
    );

    expect(positive.milliEuros, 12345);
    // The card stores milli-euro precision, but the Mensa only ever charges
    // and tops up in whole cents — displayed amounts round to cents.
    expect(positive.euroAmount, '12.35');
    expect(negative.milliEuros, -1250);
    expect(negative.euroAmount, '-1.25');
  });

  test('rounds a half-cent milli-euro remainder to the nearest cent', () {
    expect(const CanteenBalance(milliEuros: 1005).euroAmount, '1.01');
    expect(const CanteenBalance(milliEuros: 12344).euroAmount, '12.34');
    expect(const CanteenBalance(milliEuros: 12346).euroAmount, '12.35');
    expect(const CanteenBalance(milliEuros: -12345).euroAmount, '-12.35');
  });

  test('rejects malformed, failed and implausible responses', () {
    for (final List<int> response in <List<int>>[
      <int>[0x91],
      <int>[0x90, 0x00],
      <int>[0x39, 0x30, 0x00, 0x00, 0x91],
      <int>[0x39, 0x30, 0x00, 0x00, 0x91, 0xae],
      // EUR 1,000.001 is beyond the documented defensive range.
      <int>[0x41, 0x42, 0x0f, 0x00, 0x91, 0x00],
      // EUR -100.001 is beyond the documented defensive range.
      <int>[0x5f, 0x79, 0xfe, 0xff, 0x91, 0x00],
    ]) {
      expect(
        () => response.length == 2
            ? CanteenBalanceApdu.validateSelection(response)
            : CanteenBalanceApdu.parseBalance(response),
        throwsA(isA<CanteenBalanceProtocolException>()),
      );
    }
  });

  test('rejects integers outside one unsigned byte as malformed', () {
    for (final List<int> response in <List<int>>[
      <int>[-1, 0x00],
      <int>[0x91, 0x100],
      <int>[-1, 0x00, 0x00, 0x00, 0x91, 0x00],
      <int>[0x00, 0x00, 0x00, 0x100, 0x91, 0x00],
    ]) {
      expect(
        () => response.length == 2
            ? CanteenBalanceApdu.validateSelection(response)
            : CanteenBalanceApdu.parseBalance(response),
        throwsA(
          isA<CanteenBalanceProtocolException>().having(
            (CanteenBalanceProtocolException error) => error.reason,
            'reason',
            CanteenBalanceProtocolFailure.malformed,
          ),
        ),
      );
    }
  });
}
