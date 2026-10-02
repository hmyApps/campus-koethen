// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:campus_koethen/core/theme/appearance_preferences.dart';
import 'package:campus_koethen/core/theme/contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A foreground/background pairing the app actually renders.
class _Pair {
  const _Pair(this.name, this.foreground, this.background, this.threshold);

  final String name;
  final Color foreground;
  final Color background;
  final double threshold;
}

List<_Pair> _pairsFor(AppColors c) => <_Pair>[
  // Body copy.
  _Pair(
    'textPrimary on background',
    c.textPrimary,
    c.background,
    Contrast.aaBody,
  ),
  _Pair('textPrimary on surface', c.textPrimary, c.surface, Contrast.aaBody),
  _Pair(
    'textSecondary on background',
    c.textSecondary,
    c.background,
    Contrast.aaBody,
  ),
  _Pair(
    'textSecondary on surface',
    c.textSecondary,
    c.surface,
    Contrast.aaBody,
  ),
  _Pair(
    'onSurfaceVariant on surfaceVariant',
    c.onSurfaceVariant,
    c.surfaceVariant,
    Contrast.aaBody,
  ),

  // Brand colour as text / icon colour. Only ever used on `surface`, which is
  // why status banners are surface coloured.
  _Pair('primary on surface', c.primary, c.surface, Contrast.aaBody),
  _Pair('primary on background', c.primary, c.background, Contrast.aaBody),
  _Pair(
    'onPrimaryContainer on primaryContainer',
    c.onPrimaryContainer,
    c.primaryContainer,
    Contrast.aaBody,
  ),

  // Filled controls.
  _Pair('onPrimary on primary', c.onPrimary, c.primary, Contrast.aaBody),
  _Pair('onAccent on accent', c.onAccent, c.accent, Contrast.aaBody),
  _Pair('onSuccess on success', c.onSuccess, c.success, Contrast.aaBody),
  _Pair('onError on error', c.onError, c.error, Contrast.aaBody),

  // Semantic accents. These are rendered as icon + text on `surface` only.
  _Pair('success on surface', c.success, c.surface, Contrast.aaBody),
  _Pair('error on surface', c.error, c.surface, Contrast.aaBody),

  // Supporting copy in the information tint, on plain paper rather than on its
  // own tinted surface.
  _Pair(
    'onSurfaceVariant on surface',
    c.onSurfaceVariant,
    c.surface,
    Contrast.aaBody,
  ),

  // The snack bar sits on `textPrimary`, not on paper — its own pairing.
  // The action colour is here because it was the gap that let a 2.9:1 button
  // label sit unnoticed in the theme until the first caller shipped it.
  _Pair(
    'snackBar content on snackBar',
    c.surface,
    c.textPrimary,
    Contrast.aaBody,
  ),
  _Pair(
    'snackBar action on snackBar',
    c.primaryContainer,
    c.textPrimary,
    Contrast.aaBody,
  ),

  // Structural rules carry layout and therefore need 3:1. The pale outline is
  // decorative only; no state or boundary depends on it alone.
  _Pair('rule on surface', c.rule, c.surface, Contrast.aaLarge),
  _Pair('rule on background', c.rule, c.background, Contrast.aaLarge),

  // The rail is drawn with alpha, and an alpha pair is invisible to a ratio
  // computed from two opaque colours. Asserting the pre-blended result is the
  // only way this floor is actually enforced.
  _Pair('rail on surface', c.railOn(c.surface), c.surface, Contrast.aaLarge),
  _Pair(
    'rail on background',
    c.railOn(c.background),
    c.background,
    Contrast.aaLarge,
  ),
  _Pair(
    'past rail on surface',
    c.railPastOn(c.surface),
    c.surface,
    Contrast.aaLarge,
  ),
  _Pair(
    'past rail on background',
    c.railPastOn(c.background),
    c.background,
    Contrast.aaLarge,
  ),
];

void main() {
  for (final AccentScheme accent in AccentScheme.values) {
    for (final Brightness brightness in Brightness.values) {
      for (final bool highContrast in <bool>[false, true]) {
        final AppColors colors = AppColors.forScheme(
          accent,
          brightness,
          highContrast: highContrast,
        );
        final ThemeData theme = switch (brightness) {
          Brightness.light =>
            highContrast
                ? AppTheme.highContrastLight(accentScheme: accent)
                : AppTheme.light(accentScheme: accent),
          Brightness.dark =>
            highContrast
                ? AppTheme.highContrastDark(accentScheme: accent)
                : AppTheme.dark(accentScheme: accent),
        };
        final String label =
            '${accent.name} ${brightness.name}'
            '${highContrast ? ' high contrast' : ''}';

        _paletteContrastTests(label, colors);
        _controlBoundaryTests(label, theme, colors);
      }
    }
  }

  group('Contrast helper', () {
    test('matches the WCAG reference values', () {
      expect(
        Contrast.ratio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        Contrast.ratio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
        closeTo(1, 0.001),
      );
      // Known reference pair: #767676 on white is exactly at the AA threshold.
      expect(
        Contrast.ratio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        greaterThanOrEqualTo(Contrast.aaBody),
      );
    });

    test('is symmetric', () {
      const Color a = Color(0xFF5B3FD0);
      const Color b = Color(0xFFF7F5F2);
      expect(Contrast.ratio(a, b), closeTo(Contrast.ratio(b, a), 1e-12));
    });
  });

  test('high contrast strengthens outlines and focus rings', () {
    for (final Brightness brightness in Brightness.values) {
      final AppColors standard = AppColors.forScheme(
        AccentScheme.pink,
        brightness,
      );
      final AppColors high = AppColors.forScheme(
        AccentScheme.pink,
        brightness,
        highContrast: true,
      );
      expect(high.highContrast, isTrue);
      expect(
        Contrast.ratio(high.outline, high.surface),
        greaterThan(Contrast.ratio(standard.outline, standard.surface)),
      );

      final ThemeData standardTheme = brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark();
      final ThemeData highTheme = brightness == Brightness.light
          ? AppTheme.highContrastLight()
          : AppTheme.highContrastDark();
      final OutlineInputBorder standardFocus =
          standardTheme.inputDecorationTheme.focusedBorder!
              as OutlineInputBorder;
      final OutlineInputBorder highFocus =
          highTheme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(
        highFocus.borderSide.width,
        greaterThan(standardFocus.borderSide.width),
      );
      expect(
        Contrast.ratio(highFocus.borderSide.color, high.surface),
        greaterThanOrEqualTo(Contrast.aaLarge),
      );
      expect(
        Contrast.ratio(highFocus.borderSide.color, high.background),
        greaterThanOrEqualTo(Contrast.aaLarge),
      );
    }
  });

  test('dark variants use genuinely dark surfaces', () {
    for (final AccentScheme accent in AccentScheme.values) {
      final AppColors colors = AppColors.forScheme(accent, Brightness.dark);
      expect(Contrast.relativeLuminance(colors.background), lessThan(0.05));
      expect(Contrast.relativeLuminance(colors.surface), lessThan(0.06));
      expect(
        Contrast.relativeLuminance(colors.surface),
        greaterThan(Contrast.relativeLuminance(colors.background)),
        reason: 'elevation is expressed by lighter surfaces',
      );
    }
  });
}

void _paletteContrastTests(String label, AppColors colors) {
  group('$label · colour pairs', () {
    for (final _Pair pair in _pairsFor(colors)) {
      test('${pair.name} meets ${pair.threshold}:1', () {
        final double ratio = Contrast.ratio(pair.foreground, pair.background);
        expect(
          ratio,
          greaterThanOrEqualTo(pair.threshold),
          reason:
              '${pair.name} is ${ratio.toStringAsFixed(2)}:1, '
              'required ${pair.threshold}:1',
        );
      });
    }

    if (colors.highContrast) {
      test('outline itself is a perceivable component boundary', () {
        for (final Color ground in <Color>[colors.surface, colors.background]) {
          expect(
            Contrast.ratio(colors.outline, ground),
            greaterThanOrEqualTo(Contrast.aaLarge),
          );
        }
      });
    }
  });
}

/// The boundaries of interactive controls, read off the built theme rather
/// than off a token.
///
/// WCAG 2.1 SC 1.4.11 asks for 3:1 on "visual information required to identify
/// user interface components". A text field is `filled` with `surface` and sits
/// on `background` or on a `Panel` (also `surface`) — 1.07:1 and 1.00:1
/// respectively — so its border is the ONLY thing that says a field is there.
/// The same holds for a switch in its off state, where track, thumb and page
/// are within 1.15:1 of one another.
///
/// Asserted against the theme, not against `AppColors`, so pointing a border
/// back at a pale token fails here rather than shipping.
void _controlBoundaryTests(String label, ThemeData theme, AppColors colors) {
  group('$label · control boundaries', () {
    final List<Color> grounds = <Color>[colors.surface, colors.background];

    Color? borderColourOf(InputBorder? border) =>
        border is OutlineInputBorder ? border.borderSide.color : null;

    test('the unfocused text field border is visible on both grounds', () {
      final Color? colour = borderColourOf(
        theme.inputDecorationTheme.enabledBorder,
      );
      expect(colour, isNotNull, reason: 'enabledBorder must be an outline');
      for (final Color ground in grounds) {
        final double ratio = Contrast.ratio(colour!, ground);
        expect(
          ratio,
          greaterThanOrEqualTo(Contrast.aaLarge),
          reason:
              'the field border is ${ratio.toStringAsFixed(2)}:1 on '
              '${ground.toARGB32().toRadixString(16)}, required '
              '${Contrast.aaLarge}:1',
        );
      }
    });

    test('the off switch has a visible track outline on both grounds', () {
      final Color? colour = theme.switchTheme.trackOutlineColor?.resolve(
        const <WidgetState>{},
      );
      expect(colour, isNotNull, reason: 'an off switch needs a track outline');
      for (final Color ground in grounds) {
        final double ratio = Contrast.ratio(colour!, ground);
        expect(
          ratio,
          greaterThanOrEqualTo(Contrast.aaLarge),
          reason:
              'the switch track outline is ${ratio.toStringAsFixed(2)}:1 on '
              '${ground.toARGB32().toRadixString(16)}, required '
              '${Contrast.aaLarge}:1',
        );
      }
    });
  });
}
