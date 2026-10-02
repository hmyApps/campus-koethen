// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/theme/app_colors.dart';
import 'package:campus_koethen/core/theme/app_metrics.dart';
import 'package:campus_koethen/core/theme/app_dimensions.dart';
import 'package:campus_koethen/core/theme/app_motion.dart';
import 'package:campus_koethen/core/theme/app_theme.dart';
import 'package:campus_koethen/core/theme/appearance_preferences.dart';
import 'package:campus_koethen/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('layout metrics', () {
    test('the one metric set never goes below the minimum touch target', () {
      // The app no longer offers a density choice; the single set it does use
      // still has to keep every row tappable.
      expect(
        AppMetrics.standard.listRowMinHeight,
        greaterThanOrEqualTo(AppSizes.minTouchTarget),
      );
    });

    test('spacing is positive and ordered', () {
      const AppMetrics m = AppMetrics.standard;
      expect(m.screenPadding, greaterThan(0));
      expect(m.cardGap, greaterThan(0));
      expect(m.sectionGap, greaterThan(m.cardGap));
    });
  });

  group('motion', () {
    test('either source alone switches reduced motion on', () {
      expect(
        AppMotion.resolve(
          systemDisablesAnimations: true,
          userPrefersReducedMotion: false,
        ).reduced,
        isTrue,
        reason: 'the operating system setting must be honoured on its own',
      );
      expect(
        AppMotion.resolve(
          systemDisablesAnimations: false,
          userPrefersReducedMotion: true,
        ).reduced,
        isTrue,
        reason: 'the in-app toggle must be honoured on its own',
      );
      expect(
        AppMotion.resolve(
          systemDisablesAnimations: false,
          userPrefersReducedMotion: false,
        ).reduced,
        isFalse,
      );
    });

    test('reduced motion means no motion, not fast motion', () {
      expect(AppMotion.suppressed.fast, Duration.zero);
      expect(AppMotion.suppressed.medium, Duration.zero);
      expect(AppMotion.suppressed.slow, Duration.zero);
    });

    test('motion tokens do not interpolate across a theme change', () {
      // Crossing from animated to reduced has to take effect at once.
      final AppMotion mid = AppMotion.enabled.lerp(AppMotion.suppressed, 0.6);
      expect(mid.reduced, isTrue);
      expect(mid.fast, Duration.zero);
    });
  });

  group('theme assembly', () {
    ThemeData themed({AppMotion motion = AppMotion.enabled}) =>
        AppTheme.light(motion: motion);

    test('carries colours, metrics, motion and type as typed extensions', () {
      final ThemeData theme = themed();
      expect(theme.extension<AppColors>(), isNotNull);
      expect(theme.extension<AppMetrics>(), isNotNull);
      expect(theme.extension<AppMotion>(), isNotNull);
      expect(theme.extension<AppTypography>(), isNotNull);
    });

    test('Albert Sans reaches every text role', () {
      final ThemeData theme = themed();
      expect(theme.textTheme.displaySmall!.fontFamily, AppFonts.display);
      expect(theme.textTheme.titleLarge!.fontFamily, AppFonts.ui);
      expect(theme.textTheme.bodyMedium!.fontFamily, AppFonts.ui);
      expect(theme.extension<AppTypography>()!.data.fontFamily, AppFonts.data);
      expect(theme.extension<AppTypography>()!.eyebrow.fontFamily, AppFonts.ui);
    });

    test('pink remains the compatible default palette', () {
      final ThemeData theme = themed();
      expect(theme.colorScheme.primary, AppColors.light.primary);
      expect(theme.extension<AppColors>()!.primary, const Color(0xFFC2185B));
      expect(AppTheme.dark().colorScheme.primary, const Color(0xFFEC6E9F));
    });

    test('every accent has stable light and dark tokens', () {
      final Set<Color> lightPrimaries = <Color>{};
      final Set<Color> darkPrimaries = <Color>{};
      for (final AccentScheme accent in AccentScheme.values) {
        final AppColors light = AppColors.forScheme(accent, Brightness.light);
        final AppColors dark = AppColors.forScheme(accent, Brightness.dark);
        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.highContrast, isFalse);
        expect(dark.highContrast, isFalse);
        lightPrimaries.add(light.primary);
        darkPrimaries.add(dark.primary);
      }
      expect(lightPrimaries, hasLength(AccentScheme.values.length));
      expect(darkPrimaries, hasLength(AccentScheme.values.length));
    });

    test('accent and high contrast participate in the theme cache key', () {
      expect(
        identical(
          AppTheme.light(accentScheme: AccentScheme.green),
          AppTheme.light(accentScheme: AccentScheme.green),
        ),
        isTrue,
      );
      expect(
        identical(
          AppTheme.light(),
          AppTheme.light(accentScheme: AccentScheme.green),
        ),
        isFalse,
      );
      expect(
        identical(AppTheme.light(), AppTheme.highContrastLight()),
        isFalse,
      );
      expect(
        AppTheme.highContrastDark().extension<AppColors>()!.highContrast,
        isTrue,
      );
    });

    test(
      'the light palette uses the supplied off-white instead of pure white',
      () {
        const Color offWhite = Color(0xFFFDFBFC);
        expect(AppColors.light.surface, offWhite);
        expect(AppColors.light.onPrimary, offWhite);
        expect(AppColors.light.onAccent, offWhite);
        expect(AppColors.light.onSuccess, offWhite);
        expect(AppColors.light.onError, offWhite);
      },
    );

    test('the metrics reach the list theme', () {
      final ThemeData theme = themed();
      expect(
        theme.listTileTheme.minTileHeight,
        AppMetrics.standard.listRowMinHeight,
      );
      expect(
        theme.listTileTheme.minTileHeight,
        greaterThanOrEqualTo(AppSizes.minTouchTarget),
      );
    });

    test('reduced motion removes the platform page transition', () {
      final ThemeData reduced = themed(motion: AppMotion.suppressed);
      final ThemeData normal = themed();
      // Same route, same child: with reduced motion the builder must hand the
      // child back untouched instead of wrapping it in a transition.
      expect(
        reduced.pageTransitionsTheme.builders[TargetPlatform.android],
        isNot(
          equals(normal.pageTransitionsTheme.builders[TargetPlatform.android]),
        ),
      );
      expect(reduced.extension<AppMotion>()!.reduced, isTrue);
    });

    test('Apple platforms keep a transition of their own', () {
      final PageTransitionsTheme transitions = themed().pageTransitionsTheme;

      // The iOS back swipe is built by the Cupertino page transition, so iOS
      // and macOS must NOT share the app's own builder — see the comment on
      // the page transitions theme in app_theme.dart.
      expect(
        transitions.builders[TargetPlatform.iOS].runtimeType,
        isNot(equals(transitions.builders[TargetPlatform.android].runtimeType)),
      );
      expect(
        transitions.builders[TargetPlatform.macOS],
        same(transitions.builders[TargetPlatform.iOS]),
      );
      // Android, Linux and Windows keep the Takt transition.
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          transitions.builders[platform],
          same(transitions.builders[TargetPlatform.android]),
        );
      }
    });

    test('reduced motion keeps the iOS transition but stops it moving', () {
      final PageTransitionsTheme reduced = themed(
        motion: AppMotion.suppressed,
      ).pageTransitionsTheme;
      final PageTransitionsTheme normal = themed().pageTransitionsTheme;

      // Same builder type as with motion on — anything else would take the
      // back swipe with it — but nothing is left to animate.
      expect(
        reduced.builders[TargetPlatform.iOS].runtimeType,
        equals(normal.builders[TargetPlatform.iOS].runtimeType),
      );
      expect(
        reduced.builders[TargetPlatform.iOS],
        isNot(same(normal.builders[TargetPlatform.iOS])),
      );
      expect(
        reduced.builders[TargetPlatform.iOS]!.transitionDuration,
        Duration.zero,
      );
      expect(reduced.builders[TargetPlatform.iOS]!.delegatedTransition, isNull);
      expect(
        normal.builders[TargetPlatform.iOS]!.transitionDuration,
        greaterThan(Duration.zero),
      );
    });

    test('dark keeps the supplied warm dark surfaces', () {
      final AppColors colors = AppTheme.dark().extension<AppColors>()!;
      expect(colors.brightness, Brightness.dark);
      expect(colors.background, const Color(0xFF1B1418));
      expect(colors.surface, const Color(0xFF251D22));
    });

    test('the same inputs give back the very same theme', () {
      // Identity, not equality: the root widget rebuilds on every settings
      // change and hands the result to `AnimatedTheme`. A new instance there
      // starts a theme transition — and a rebuild of the whole tree — for a
      // theme that did not actually change.
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
      expect(
        identical(
          AppTheme.light(motion: AppMotion.suppressed),
          AppTheme.light(motion: AppMotion.suppressed),
        ),
        isTrue,
      );
    });

    test('a different motion setting still gives a different theme', () {
      expect(
        identical(
          AppTheme.light(),
          AppTheme.light(motion: AppMotion.suppressed),
        ),
        isFalse,
      );
      expect(
        AppTheme.light(
          motion: AppMotion.suppressed,
        ).extension<AppMotion>()!.reduced,
        isTrue,
      );
      expect(AppTheme.light().extension<AppMotion>()!.reduced, isFalse);
      expect(identical(AppTheme.light(), AppTheme.dark()), isFalse);
    });

    test('a caller-made motion is assembled rather than cached', () {
      // Only the two shared constants are cached, so an invented motion can
      // never grow the map — and still gets a correct theme.
      const AppMotion custom = AppMotion(
        reduced: false,
        fast: Duration(milliseconds: 10),
        medium: Duration(milliseconds: 20),
        slow: Duration(milliseconds: 30),
        curve: Curves.linear,
      );
      final ThemeData first = AppTheme.light(motion: custom);
      final ThemeData second = AppTheme.light(motion: custom);
      expect(identical(first, second), isFalse);
      expect(first.extension<AppMotion>()!.fast, custom.fast);
    });
  });
}
