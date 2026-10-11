// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:campus_koethen/core/theme/app_icons.dart";

import '../../../app/app_modules.dart';
import '../../../app/navigation_config.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// Picks and orders the four modules of the bottom navigation bar.
///
/// The screen edits a **local draft** and only writes through once exactly four
/// modules are selected.
///
/// Writing on every tap looked simpler and did not work: the stored
/// configuration is always repaired to exactly four, so removing one
/// immediately refilled it from the defaults and the control appeared to do
/// nothing. A draft lets the user take one away, put another back, and commit a
/// state the store can actually hold.
///
/// More is shown as a fixed, disabled row rather than hidden: the user can see
/// the whole bar they are configuring, and why the last entry cannot change.
class NavigationSettingsScreen extends ConsumerStatefulWidget {
  const NavigationSettingsScreen({super.key});

  @override
  ConsumerState<NavigationSettingsScreen> createState() =>
      _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState
    extends ConsumerState<NavigationSettingsScreen> {
  List<AppModule>? _draft;

  List<AppModule> get _chosen =>
      _draft ?? ref.read(settingsProvider).navigation.tabs;

  void _commit(List<AppModule> next) {
    setState(() => _draft = next);
    // Only a complete selection is a valid bar, so only that is persisted.
    if (next.length == NavigationConfig.tabCount) {
      ref.read(settingsProvider.notifier).setNavigationTabs(next);
    }
  }

  void _add(AppModule module) {
    if (_chosen.length >= NavigationConfig.tabCount) return;
    _commit(<AppModule>[..._chosen, module]);
  }

  void _remove(AppModule module) =>
      _commit(_chosen.where((AppModule m) => m != module).toList());

  /// Deliberately without the classic `if (newIndex > oldIndex) newIndex--`.
  ///
  /// That correction belongs to the deprecated `onReorder` callback, which
  /// reports the insertion point in the list *before* the item is taken out.
  /// `onReorderItem` — the one wired up below — already adjusts for the
  /// removal, so subtracting again would move a downward drag one place too
  /// far. Checked against the Flutter source and pinned by a widget test,
  /// because this reads exactly like a missing off-by-one guard (SET-5).
  void _reorder(int oldIndex, int newIndex) {
    final List<AppModule> next = _chosen.toList();
    next.insert(newIndex, next.removeAt(oldIndex));
    _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<AppModule> chosen = _chosen;
    final bool full = chosen.length >= NavigationConfig.tabCount;

    return ScreenScaffold(
      eyebrow: ModuleCategory.app.label(l10n),
      title: l10n.settingsNavigation,
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              l10n.settingsNavigationHint,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          // An incomplete draft is not an error, but it is not saved either —
          // say so rather than letting the user believe it was.
          if (!full)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    AppIcons.info_outline,
                    size: AppSizes.iconSmall,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      l10n.settingsSelectExactlyFour,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

          _Heading(text: l10n.settingsNavigationActive),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorder,
            children: <Widget>[
              for (int i = 0; i < chosen.length; i++)
                _ActiveRow(
                  key: ValueKey<String>('tab-${chosen[i].storageValue}'),
                  module: chosen[i],
                  index: i,
                  onRemove: () => _remove(chosen[i]),
                ),
            ],
          ),
          // Always last, always locked.
          ListTile(
            leading: const Icon(AppIcons.more_horiz),
            title: Text(l10n.navMore),
            trailing: const Icon(AppIcons.lock_outline),
            enabled: false,
          ),

          _Heading(text: l10n.settingsNavigationAvailable),
          for (final ModuleCategory category in ModuleCategory.values)
            ..._availableIn(category, chosen, l10n, full),
        ],
      ),
    );
  }

  /// The pinnable modules of one category that are not on the bar yet.
  ///
  /// A temporarily unavailable module (greyed out in More) is not offered
  /// either: as a tab it would open its screen directly and bypass the lock.
  ///
  /// Non-pinnable modules never appear here: settings and the about page are
  /// not places to spend time in, and offering them would only produce a bar
  /// slot nobody wants.
  List<Widget> _availableIn(
    ModuleCategory category,
    List<AppModule> chosen,
    AppLocalizations l10n,
    bool full,
  ) {
    final List<AppModule> modules = AppModule.inCategory(category)
        .where(
          (AppModule m) =>
              m.pinnable &&
              !m.isTemporarilyUnavailable &&
              !m.isExcludedFromBuild &&
              !chosen.contains(m),
        )
        .toList(growable: false);
    if (modules.isEmpty) return const <Widget>[];
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxs,
        ),
        child: Semantics(
          header: true,
          child: Text(
            category.label(l10n),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ),
      for (final AppModule module in modules)
        ListTile(
          leading: Icon(module.icon),
          title: Text(module.title(l10n)),
          // Full: leave it disabled rather than evicting someone else's pick
          // behind their back.
          trailing: IconButton(
            icon: const Icon(AppIcons.add_circle_outline),
            tooltip: l10n.settingsNavigationAdd,
            onPressed: full ? null : () => _add(module),
          ),
          enabled: !full,
          onTap: full ? null : () => _add(module),
        ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.xs,
    ),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

/// One row of the bar, draggable and removable.
class _ActiveRow extends StatelessWidget {
  const _ActiveRow({
    required this.module,
    required this.index,
    required this.onRemove,
    super.key,
  });

  final AppModule module;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return ListTile(
      leading: Icon(module.icon),
      title: Text(module.title(l10n)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(AppIcons.remove_circle_outline),
            tooltip: l10n.settingsNavigationRemove,
            onPressed: onRemove,
          ),
          // An explicit handle rather than a long press on the whole row:
          // a screen reader user gets a labelled control, and the remove
          // button stays tappable.
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: l10n.settingsNavigationReorder,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Icon(AppIcons.drag_handle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
