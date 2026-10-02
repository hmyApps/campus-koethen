// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/cupertino.dart'
    show CupertinoPageTransition, CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'appearance_preferences.dart';
import 'app_metrics.dart';
import 'app_dimensions.dart';
import 'app_motion.dart';
import 'app_typography.dart';

/// Builds the Material 3 themes from the typed tokens of the "Takt" system.
///
/// ## Depth without shadows
///
/// Not a single component in this theme casts a shadow. The app is printed
/// matter: a card is an off-white sheet on warm paper with a hairline around it, and
/// in the dark palette it is a lighter surface than the one it sits on. Both
/// readings survive a greyscale screenshot, which a drop shadow at 8 % opacity
/// does not.
///
/// ## One radius
///
/// Everything with a body uses [AppRadius.card]. Sheets and dialogs are the
/// only exception, because they are the only surfaces that behave like objects.
/// See `AppRadius` for the argument.
///
/// Reduced motion is applied **here**, so a screen never has to know which
/// mode is active. It reads
/// `context.colors`, `context.metrics`, `context.type` and `context.motion` and
/// gets the resolved answer.
abstract final class AppTheme {
  /// The interface face. Exposed because a few places set a family explicitly
  /// on a style they build themselves.
  static const String fontFamily = AppFonts.ui;

  static ThemeData light({
    AccentScheme accentScheme = AccentScheme.pink,
    AppMotion motion = AppMotion.enabled,
  }) => _resolved(AppColors.forScheme(accentScheme, Brightness.light), motion);

  static ThemeData dark({
    AccentScheme accentScheme = AccentScheme.pink,
    AppMotion motion = AppMotion.enabled,
  }) => _resolved(AppColors.forScheme(accentScheme, Brightness.dark), motion);

  static ThemeData highContrastLight({
    AccentScheme accentScheme = AccentScheme.pink,
    AppMotion motion = AppMotion.enabled,
  }) => _resolved(
    AppColors.forScheme(accentScheme, Brightness.light, highContrast: true),
    motion,
  );

  static ThemeData highContrastDark({
    AccentScheme accentScheme = AccentScheme.pink,
    AppMotion motion = AppMotion.enabled,
  }) => _resolved(
    AppColors.forScheme(accentScheme, Brightness.dark, highContrast: true),
    motion,
  );

  /// The assembled themes, one per palette and motion setting.
  ///
  /// The root widget rebuilds whenever ANY setting changes — the language, the
  /// theme mode, a pinned tab, a channel subscription — and asked for both the
  /// light and the dark theme on every one of those rebuilds. Assembling a
  /// `ThemeData` is not free (a full `ColorScheme`, a full `TextTheme` and
  /// every component theme), and it had a second, larger cost: the theme
  /// extensions carry no value equality, so a freshly built theme is never
  /// EQUAL to the previous one. `MaterialApp` hands the theme to an
  /// `AnimatedTheme`, which therefore ran a theme transition — and with it a
  /// rebuild of the whole tree — every time an unrelated setting changed.
  ///
  /// Returning the same instance for the same inputs removes both. The map is
  /// bounded to the registered accent, brightness, contrast and motion
  /// combinations. A caller-made [AppMotion] is assembled fresh, so it can
  /// never grow this cache.
  static final Map<(AppColors, AppMotion), ThemeData> _assembled =
      <(AppColors, AppMotion), ThemeData>{};

  static ThemeData _resolved(AppColors colors, AppMotion motion) {
    final bool cacheable =
        identical(motion, AppMotion.enabled) ||
        identical(motion, AppMotion.suppressed);
    if (!cacheable) return _build(colors, motion);
    return _assembled[(colors, motion)] ??= _build(colors, motion);
  }

  static ThemeData _build(AppColors colors, AppMotion motion) {
    const AppMetrics metrics = AppMetrics.standard;
    final AppTypography type = AppTypography.of(
      primaryInk: colors.textPrimary,
      secondaryInk: colors.textSecondary,
    );
    final TextTheme text = AppTypography.textTheme(
      primaryInk: colors.textPrimary,
      secondaryInk: colors.textSecondary,
    );

    final ColorScheme scheme = ColorScheme(
      brightness: colors.brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: colors.onSurfaceVariant,
      onSecondary: colors.background,
      secondaryContainer: colors.surfaceVariant,
      onSecondaryContainer: colors.onSurfaceVariant,
      tertiary: colors.success,
      onTertiary: colors.onSuccess,
      error: colors.error,
      onError: colors.onError,
      errorContainer: colors.surface,
      onErrorContainer: colors.error,
      surface: colors.surface,
      onSurface: colors.onSurface,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: colors.background,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceVariant,
      surfaceContainerHighest: colors.surfaceVariant,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.outline,
      outlineVariant: colors.outline,
      inverseSurface: colors.textPrimary,
      onInverseSurface: colors.surface,
      inversePrimary: colors.primaryDark,
      shadow: const Color(0x00000000),
      scrim: const Color(0x99000000),
    );

    final BorderSide hairline = BorderSide(
      color: colors.outline,
      width: colors.highContrast ? AppSizes.rule : AppSizes.hairline,
    );
    final double focusWidth = colors.highContrast
        ? AppSizes.beam
        : AppSizes.rule;
    final Color focusRingColor = colors.highContrast
        ? colors.rule
        : colors.primary;
    final OutlinedBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(metrics.cardRadius),
      side: hairline,
    );

    OutlineInputBorder fieldBorder(Color colour, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide(color: colour, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      colorScheme: scheme,
      fontFamily: AppFonts.ui,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      focusColor: colors.primary.withValues(
        alpha: colors.highContrast ? 0.28 : 0.16,
      ),
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[colors, metrics, motion, type],
      splashFactory: InkSparkle.splashFactory,
      // Reduced motion must also silence the transitions Flutter itself
      // drives; a token the app reads is not enough for page routes.
      //
      // Apple's platforms are the exception. There the interactive back swipe
      // lives INSIDE the page transition — `CupertinoPageTransitionsBuilder`
      // is what wraps a pushed page in the edge-gesture detector — so a
      // builder that only returns a fade takes the platform's back gesture
      // with it. They keep the Cupertino transition, reduced motion included;
      // see [_TaktCupertinoPageTransitionsBuilder].
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          for (final TargetPlatform platform in <TargetPlatform>[
            TargetPlatform.android,
            TargetPlatform.linux,
            TargetPlatform.windows,
          ])
            platform: motion.reduced
                ? const _NoTransitionsBuilder()
                : const _TaktPageTransitionsBuilder(),
          for (final TargetPlatform platform in <TargetPlatform>[
            TargetPlatform.iOS,
            TargetPlatform.macOS,
          ])
            platform: motion.reduced
                ? const _TaktCupertinoPageTransitionsBuilder(
                    reducedMotion: true,
                  )
                : const _TaktCupertinoPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),

      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),

      dividerTheme: DividerThemeData(
        color: colors.outline,
        space: AppSpacing.lg,
        thickness: AppSizes.hairline,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        minVerticalPadding: AppSpacing.sm,
        // Pull every row onto the same 24 dp measure as the headings.
        contentPadding: EdgeInsets.symmetric(horizontal: metrics.screenPadding),
        // Never below the minimum touch target.
        minTileHeight: metrics.listRowMinHeight,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      // The app draws its own bottom bar (see `TaktNavigationBar`), but the
      // Material one is still themed: a sheet or a nested route that reaches
      // for it must not arrive in an unstyled default.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? text.labelMedium!.copyWith(color: colors.textPrimary)
              : text.labelMedium!.copyWith(color: colors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.textSecondary,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        selectedColor: colors.primaryContainer,
        checkmarkColor: colors.onPrimaryContainer,
        side: hairline,
        labelStyle: text.labelMedium!.copyWith(color: colors.onSurfaceVariant),
        secondaryLabelStyle: text.labelMedium!.copyWith(
          color: colors.onPrimaryContainer,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: colors.surfaceVariant,
              disabledForegroundColor: colors.textSecondary,
              elevation: 0,
              minimumSize: const Size(
                AppSizes.minTouchTarget,
                AppSizes.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              textStyle: text.labelLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (Set<WidgetState> states) =>
                    states.contains(WidgetState.focused)
                    ? BorderSide(color: focusRingColor, width: focusWidth)
                    : null,
              ),
            ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: colors.primary,
              side: BorderSide(
                color: colors.primary,
                width: colors.highContrast ? AppSizes.rule : AppSizes.hairline,
              ),
              minimumSize: const Size(
                AppSizes.minTouchTarget,
                AppSizes.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              textStyle: text.labelLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (Set<WidgetState> states) => BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? focusRingColor
                      : colors.primary,
                  width: states.contains(WidgetState.focused)
                      ? focusWidth
                      : (colors.highContrast
                            ? AppSizes.rule
                            : AppSizes.hairline),
                ),
              ),
            ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(
                AppSizes.minTouchTarget,
                AppSizes.minTouchTarget,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (Set<WidgetState> states) =>
                    states.contains(WidgetState.focused)
                    ? BorderSide(color: focusRingColor, width: focusWidth)
                    : null,
              ),
            ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: colors.surface,
          foregroundColor: colors.textSecondary,
          selectedBackgroundColor: colors.primaryContainer,
          selectedForegroundColor: colors.onPrimaryContainer,
          side: hairline,
          textStyle: text.labelMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hintStyle: text.bodyMedium!.copyWith(color: colors.textSecondary),
        labelStyle: text.labelMedium!.copyWith(color: colors.textSecondary),
        floatingLabelStyle: text.labelMedium!.copyWith(color: colors.primary),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall!.copyWith(color: colors.error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        // NOT `outline`: a field is filled with `surface` and sits on
        // `background` (1.07:1) or on a Panel, which is `surface` too (1.00:1).
        // Its border is therefore the only thing that says a field is there,
        // and WCAG 2.1 SC 1.4.11 asks for 3:1 on exactly that. `textSecondary`
        // clears it and is already the boundary of the unchecked checkbox
        // below, so the two controls read as one family.
        border: fieldBorder(colors.textSecondary, AppSizes.hairline),
        enabledBorder: fieldBorder(colors.textSecondary, AppSizes.hairline),
        focusedBorder: fieldBorder(focusRingColor, focusWidth),
        errorBorder: fieldBorder(colors.error, AppSizes.hairline),
        focusedErrorBorder: fieldBorder(colors.error, focusWidth),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surfaceVariant,
        ),
        // Off, nothing else distinguishes the control: track
        // (`surfaceVariant`), thumb (`surface`) and the page behind it are all
        // within 1.15:1 of one another, so the outline carries the whole
        // boundary and owes the same 3:1 as the field border. On, the accent
        // track already carries it and a ring would only add noise.
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.textSecondary,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color>(colors.onPrimary),
        side: BorderSide(color: colors.textSecondary, width: AppSizes.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card / 2),
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textSecondary,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceVariant,
        circularTrackColor: colors.surfaceVariant,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: colors.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.textPrimary,
        contentTextStyle: text.bodyMedium!.copyWith(color: colors.surface),
        // Not `accent`: the snack bar sits on `textPrimary`, and the accent on
        // that ink is 2.9:1 (light) / 2.5:1 (dark) — a button label nobody can
        // read. The container tint keeps the action brand-coloured and clears
        // AA in both palettes; `theme_contrast_test` now asserts the pair, so
        // the first snack bar that actually carries an action cannot ship the
        // old value back.
        actionTextColor: colors.primaryContainer,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        textStyle: text.labelMedium!.copyWith(color: colors.surface),
      ),

      iconTheme: IconThemeData(color: colors.textPrimary, size: AppSizes.icon),
    );
  }
}

/// The app's page transition: a short rise and a fade, nothing else.
///
/// Printed matter does not zoom. A page arrives by being set down — eight
/// logical pixels of upward travel and an opacity ramp — which is quick enough
/// to feel instant on a phone and still tells the eye that the surface changed.
/// The outgoing page only fades: two pages sliding past each other is a depth
/// cue this design has no use for.
class _TaktPageTransitionsBuilder extends PageTransitionsBuilder {
  const _TaktPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// The iOS and macOS page transition: the platform's own, on purpose.
///
/// On Apple's platforms the interactive back swipe is not a separate gesture
/// the app could add on top — it is built by the page transition itself.
/// `CupertinoRouteTransitionMixin.buildPageTransitions` wraps the page in the
/// edge-gesture detector that drives the route's own animation, so a
/// transitions builder that returns anything else silently removes the swipe
/// and leaves the back arrow as the only way out. That is exactly what the
/// app's own [_TaktPageTransitionsBuilder] did here.
///
/// The gesture asks nothing of the routes: `popGestureEnabled` already refuses
/// on the first page of the enclosing navigator — which, under
/// `StatefulShellRoute`, is each tab's own root — on a route that would veto
/// its pop, and while a transition is still running. A branch root therefore
/// has no back swipe and no tab can be swiped shut.
///
/// ## Reduced motion
///
/// A documented deviation. Reduced motion cannot flatten this transition the
/// way it flattens the others, because removing it removes the gesture. So
/// the transition stays and its ANIMATIONS are pinned instead: a push arrives
/// at rest, the page underneath does not travel, and the route settles in no
/// time at all.
///
/// The one thing that still moves is the drag itself. While a back swipe is in
/// progress the real animations are used again, so the page follows the
/// finger, can be pulled back, and lands where the reader let go. That is
/// direct manipulation rather than motion the app plays at the reader, and
/// without it the gesture would be unusable: nothing on screen would say the
/// swipe had begun, or that releasing it early had cancelled it.
class _TaktCupertinoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _TaktCupertinoPageTransitionsBuilder({this.reducedMotion = false});

  /// Whether the reader asked for reduced motion. See the class comment for
  /// what stays and what goes.
  final bool reducedMotion;

  @override
  Duration get transitionDuration => reducedMotion
      ? Duration.zero
      : CupertinoRouteTransitionMixin.kTransitionDuration;

  /// Only meaningful while something is actually animating.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      reducedMotion ? null : CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // `popGestureInProgress` reads the navigator, which a route being torn
    // down no longer has.
    final bool dragging = route.navigator != null && route.popGestureInProgress;
    final bool animated = !reducedMotion || dragging;
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      route,
      context,
      animated ? animation : kAlwaysCompleteAnimation,
      animated ? secondaryAnimation : kAlwaysDismissedAnimation,
      child,
    );
  }
}

/// A page transition that does not move anything.
///
/// Used when reduced motion is active. `PageTransitionsBuilder` has no
/// built-in "none" variant, and returning the child unchanged is the only way
/// to remove the platform slide without also removing the route itself.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
