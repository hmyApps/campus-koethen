// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/locale/locale_mode.dart';
import '../core/prefs/settings_controller.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/appearance_preferences.dart';
import '../core/theme/app_theme.dart';
import '../features/campusmap/presentation/room_catalog_refresh_host.dart';
import '../features/canteen/presentation/canteen_balance_launch_host.dart';
import '../features/notifications/presentation/notification_host.dart';
import '../l10n/l10n.dart';
import 'app_router.dart';
import 'app_sync_host.dart';

/// Root widget of the app.
///
/// Owns the theme mode, the explicitly selected locale and the router.
class CampusApp extends ConsumerWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The root only depends on presentation settings. Watching the complete
    // AppSettings object rebuilt MaterialApp, the router and every visible
    // branch when an unrelated preference changed (canteen, timetable, map,
    // onboarding or mail attachments).
    final (
      LocaleMode localeMode,
      ThemeMode themeMode,
      AccentScheme accentScheme,
      bool reducedMotion,
    ) = ref.watch(
      settingsProvider.select(
        (AppSettings settings) => (
          settings.localeMode,
          settings.themeMode,
          settings.accentScheme,
          settings.reducedMotion,
        ),
      ),
    );

    // Reduced motion has two sources and either one is enough. The operating
    // system's own accessibility switch is read here, at the root, so a change
    // to it takes effect without restarting the app.
    final AppMotion motion = AppMotion.resolve(
      systemDisablesAnimations: MediaQuery.disableAnimationsOf(context),
      userPrefersReducedMotion: reducedMotion,
    );

    return MaterialApp.router(
      onGenerateTitle: (BuildContext context) => context.l10n.appTitle,
      // The notification runtime needs a locale for the Android channel names
      // and a navigator for a tap to land in, so it wraps the router's output
      // rather than sitting above the MaterialApp.
      builder: (BuildContext context, Widget? child) =>
          CanteenBalanceLaunchHost(
            child: NotificationHost(
              child: AppSyncHost(
                child: RoomCatalogRefreshHost(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accentScheme: accentScheme, motion: motion),
      darkTheme: AppTheme.dark(accentScheme: accentScheme, motion: motion),
      highContrastTheme: AppTheme.highContrastLight(
        accentScheme: accentScheme,
        motion: motion,
      ),
      highContrastDarkTheme: AppTheme.highContrastDark(
        accentScheme: accentScheme,
        motion: motion,
      ),
      themeMode: themeMode,
      locale: localeMode.locale,
      supportedLocales: AppLocales.supported,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
