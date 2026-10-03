// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../core/network/api_configuration_notice.dart';
import '../core/prefs/settings_controller.dart';
import '../core/environment/app_environment_repository.dart';
import '../core/widgets/test_environment_notice.dart';
import '../l10n/l10n.dart';
import 'app_modules.dart';
import 'navigation_config.dart';
import 'takt_navigation_bar.dart';

/// Bottom navigation shell.
///
/// The router owns **one branch per [AppModule]**, in enum order, plus a final
/// branch for More. A branch index is therefore just the module's index, and
/// More is the last one — no lookup table can drift out of sync.
///
/// A module the user navigated to without it being on the bar — grades opened
/// from More, say — has no tab of its own. Rather than leaving nothing
/// selected, the bar then highlights More, which is where that module was
/// reached from and where it can be reached again.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Branch index of the More tab: one past the last pinnable module.
  ///
  /// The router lays out one branch per pinnable module, in enum order, and
  /// More last. That only works while the pinnable modules are the leading
  /// values of the enum — an invariant `app_modules_test` asserts, because
  /// breaking it would silently point every tab at the wrong screen.
  static int get moreBranchIndex => AppModule.pinnableModules.length;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final NavigationConfig config = ref.watch(
      settingsProvider.select((AppSettings s) => s.navigation),
    );
    final List<AppModule> tabs = config.tabs;
    final bool discloseUserTestData =
        ref.watch(appEnvironmentProvider).value?.value.userTestData ?? false;
    final bool showApiConfigurationNotice = shouldShowApiConfigurationNotice(
      ref.watch(apiConfigurationProblemProvider),
    );
    final bool topInsetConsumed =
        discloseUserTestData || showApiConfigurationNotice;

    /// Branch index of each bar entry: the four modules, then More.
    int branchOf(int barIndex) =>
        barIndex < tabs.length ? tabs[barIndex].index : moreBranchIndex;

    // Branch index -> bar index. Anything not on the bar falls back to More.
    int selected = tabs.indexWhere(
      (AppModule m) => m.index == navigationShell.currentIndex,
    );
    if (selected == -1) selected = tabs.length;

    return Scaffold(
      body: Column(
        children: <Widget>[
          if (discloseUserTestData) const TestEnvironmentNotice(),
          // A build with no (or a plaintext) Campus API address cannot load
          // anything. Said once at the top of the shell rather than as a
          // generic network error on every screen.
          if (showApiConfigurationNotice)
            discloseUserTestData
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: const ApiConfigurationNotice(),
                  )
                : const ApiConfigurationNotice(),
          // The notice has already spent the status bar inset on itself. Left
          // in place, every screen below it applies its own `SafeArea` to the
          // same inset and opens with a second empty strip.
          Expanded(
            child: topInsetConsumed
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: navigationShell,
                  )
                : navigationShell,
          ),
        ],
      ),
      bottomNavigationBar: TaktNavigationBar(
        semanticLabel: l10n.navigationSemanticLabel,
        selectedIndex: selected,
        onSelected: (int barIndex) => navigationShell.goBranch(
          branchOf(barIndex),
          // Tapping the tab you are already on returns to that module's
          // root — the behaviour both platforms have trained users to expect.
          initialLocation: branchOf(barIndex) == navigationShell.currentIndex,
        ),
        destinations: <TaktDestination>[
          for (final AppModule module in tabs)
            TaktDestination(
              icon: module.icon,
              selectedIcon: module.selectedIcon,
              label: module.shortTitle(l10n),
              tooltip: module.title(l10n),
            ),
          TaktDestination(
            icon: AppIcons.grid_on_outlined,
            selectedIcon: AppIcons.grid_on_outlined,
            label: l10n.navMore,
            tooltip: l10n.navMore,
          ),
        ],
      ),
    );
  }
}
