// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/settings_controller.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/l10n.dart';
import '../application/campus_map_providers.dart';
import '../domain/map_catalog.dart';

/// The settings row for the building the campus map opens on.
///
/// The onboarding offers the same choice and promises it can be changed later
/// in the settings; this row is where that happens.
class DefaultBuildingTile extends ConsumerWidget {
  const DefaultBuildingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final String? key = ref.watch(
      settingsProvider.select((AppSettings s) => s.defaultBuildingKey),
    );
    final MapBuilding? building = ref
        .watch(mapCatalogProvider)
        .value
        ?.building(key);

    return ListTile(
      leading: const Icon(AppIcons.map_outlined),
      title: Text(l10n.settingsDefaultBuilding),
      // A key the bundled catalogue no longer knows is as good as none: the
      // map falls back to its first building in that case.
      subtitle: Text(
        building?.name.resolve(locale) ?? l10n.settingsDefaultBuildingNone,
      ),
      trailing: const Icon(AppIcons.chevron_right),
      onTap: () => showDefaultBuildingPickerSheet(context),
    );
  }
}

/// Opens the default building picker as a modal bottom sheet.
Future<void> showDefaultBuildingPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: AppSpacing.lg),
        child: _DefaultBuildingSheet(),
      ),
    ),
  );
}

class _DefaultBuildingSheet extends ConsumerWidget {
  const _DefaultBuildingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<MapCatalog> catalog = ref.watch(mapCatalogProvider);
    final String? chosen = ref.watch(
      settingsProvider.select((AppSettings s) => s.defaultBuildingKey),
    );

    return switch (catalog) {
      AsyncLoading<MapCatalog>() when !catalog.hasValue => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: LoadingView(),
      ),
      AsyncError<MapCatalog>(:final Object error) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ErrorView(
          failure: error,
          onRetry: () => ref.invalidate(mapCatalogProvider),
        ),
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.settingsDefaultBuilding,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          DefaultBuildingOptions(
            buildings: catalog.requireValue.buildings,
            chosen: chosen,
            offerNone: true,
            onChanged: (String? key) async {
              await ref.read(settingsProvider.notifier).setDefaultBuilding(key);
              if (context.mounted) await Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    };
  }
}

/// One radio row per building, shared by the onboarding and the settings.
class DefaultBuildingOptions extends StatelessWidget {
  const DefaultBuildingOptions({
    required this.buildings,
    required this.chosen,
    required this.onChanged,
    this.offerNone = false,
    super.key,
  });

  final List<MapBuilding> buildings;
  final String? chosen;
  final ValueChanged<String?> onChanged;

  /// Adds a "not set" row, so a choice can be taken back again.
  final bool offerNone;

  /// Stands in for "no building" inside the radio group, which needs a value
  /// for every row. Never stored: [onChanged] receives `null` for it.
  static const String _none = '';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String locale = Localizations.localeOf(context).languageCode;
    final bool known = buildings.any(
      (MapBuilding building) => building.buildingKey == chosen,
    );

    return RadioGroup<String>(
      groupValue: known ? chosen : (offerNone ? _none : null),
      onChanged: (String? key) => onChanged(key == _none ? null : key),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (offerNone)
            RadioListTile<String>.adaptive(
              value: _none,
              title: Text(l10n.settingsDefaultBuildingNone),
            ),
          for (final MapBuilding building in buildings)
            RadioListTile<String>.adaptive(
              value: building.buildingKey,
              title: Text(building.name.resolve(locale)),
            ),
        ],
      ),
    );
  }
}
