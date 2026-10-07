// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Centrally defined, high-saturation calendar accents. Foreground contrast is
/// computed by the rendering components; colour never carries identity alone.
enum CalendarPalette {
  grey(0xFF616161),
  yellow(0xFFF9A825),
  blue(0xFF1565C0),
  green(0xFF2E7D32),
  pink(0xFFAD1457),
  purple(0xFF6A1B9A),
  orange(0xFFE65100),
  teal(0xFF00796B);

  const CalendarPalette(this.argb);

  final int argb;
}
