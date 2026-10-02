// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Synthetic DESFire response fixtures. They contain no UID, card number or
/// response captured from a real person or card.
abstract final class CanteenBalanceResponses {
  static const List<int> selected = <int>[0x91, 0x00];

  /// 12_345 milli-euro = EUR 12.345, Int32 little endian + DESFire status.
  static const List<int> positive = <int>[0x39, 0x30, 0x00, 0x00, 0x91, 0x00];

  /// -1_250 milli-euro = EUR -1.250, Int32 little endian + status.
  static const List<int> negative = <int>[0x1e, 0xfb, 0xff, 0xff, 0x91, 0x00];
}
