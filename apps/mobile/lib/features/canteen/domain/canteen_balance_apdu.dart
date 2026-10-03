// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:typed_data';

/// One transient card balance, represented exactly in milli-euro.
///
/// The card format stores an Int32 which is divided by 1000 for EUR. Keeping
/// the integer and exposing a decimal string avoids binary floating point for
/// a money value.
class CanteenBalance {
  const CanteenBalance({required this.milliEuros});

  final int milliEuros;

  /// The balance rounded to whole cents, exactly like every Mensa charge or
  /// top-up: the card's milli-euro precision never produces a smaller unit
  /// the reader would need to show.
  String get euroAmount {
    final int absoluteCents = (milliEuros.abs() + 5) ~/ 10;
    final bool negative = milliEuros < 0 && absoluteCents != 0;
    final String fraction = (absoluteCents % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}${absoluteCents ~/ 100}.$fraction';
  }
}

enum CanteenBalanceProtocolFailure { malformed, status, implausible }

/// A deliberately data-free protocol failure.
///
/// Never include raw NFC responses here: exception strings may reach crash
/// reports or development logs even though the production reader logs none.
class CanteenBalanceProtocolException implements Exception {
  const CanteenBalanceProtocolException(this.reason);

  final CanteenBalanceProtocolFailure reason;

  @override
  String toString() => 'CanteenBalanceProtocolException(${reason.name})';
}

/// The complete, read-only application protocol of the Mensa balance reader.
abstract final class CanteenBalanceApdu {
  /// Select DESFire application `5F8415`.
  static const List<int> selectApplication = <int>[
    0x90,
    0x5a,
    0x00,
    0x00,
    0x03,
    0x5f,
    0x84,
    0x15,
    0x00,
  ];

  /// Read value file 1. No write command exists anywhere in this feature.
  static const List<int> readBalance = <int>[
    0x90,
    0x6c,
    0x00,
    0x00,
    0x01,
    0x01,
    0x00,
  ];

  /// Defensive product range: EUR -100.000 through EUR 1,000.000.
  ///
  /// The Studentenwerk currently offers top-ups in amounts no larger than
  /// EUR 50. The deliberately generous upper bound prevents ordinary cards
  /// from being rejected while still failing closed on byte-order mistakes,
  /// unrelated files and corrupt data.
  static const int minimumMilliEuros = -100000;
  static const int maximumMilliEuros = 1000000;

  static void validateSelection(List<int> response) {
    if (response.length != 2 || _containsInvalidByte(response)) {
      throw const CanteenBalanceProtocolException(
        CanteenBalanceProtocolFailure.malformed,
      );
    }
    _validateStatus(response[0], response[1]);
  }

  static CanteenBalance parseBalance(List<int> response) {
    if (response.length != 6 || _containsInvalidByte(response)) {
      throw const CanteenBalanceProtocolException(
        CanteenBalanceProtocolFailure.malformed,
      );
    }
    _validateStatus(response[4], response[5]);

    final int milliEuros = ByteData.sublistView(
      Uint8List.fromList(response),
      0,
      4,
    ).getInt32(0, Endian.little);
    if (milliEuros < minimumMilliEuros || milliEuros > maximumMilliEuros) {
      throw const CanteenBalanceProtocolException(
        CanteenBalanceProtocolFailure.implausible,
      );
    }
    return CanteenBalance(milliEuros: milliEuros);
  }

  static void _validateStatus(int sw1, int sw2) {
    // Native DESFire commands wrapped as ISO-DEP answer with 91 00. Accepting
    // generic 90 00 would weaken detection of a wrong card/application.
    if (sw1 != 0x91 || sw2 != 0x00) {
      throw const CanteenBalanceProtocolException(
        CanteenBalanceProtocolFailure.status,
      );
    }
  }

  static bool _containsInvalidByte(List<int> response) =>
      response.any((int byte) => byte < 0 || byte > 0xff);
}
