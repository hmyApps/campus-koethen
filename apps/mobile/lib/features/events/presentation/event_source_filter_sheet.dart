// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../application/event_providers.dart';
import '../application/event_sort_order.dart';
import '../application/event_source_filter.dart';
import '../domain/event_sort.dart';

/// The event overview's own, eigenständiger multi-select source filter — a
/// modal bottom sheet with "Alle auswählen"/"Alle abwählen" and per-source
/// checkboxes, entirely separate from the news feed's channel filter and the
/// calendar's public-calendar selection — plus the overview's "Sortierung"
/// (chronological or newest first), which applies to the current and the
/// past section alike.
Future<void> showEventSourceFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _EventSourceFilterSheet(),
  );
}

class _EventSourceFilterSheet extends ConsumerWidget {
  const _EventSourceFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final List<EventSourceOption> options =
        ref.watch(eventSourceOptionsProvider).value ??
        const <EventSourceOption>[];
    final EventSourceFilterState filter = ref.watch(eventSourceFilterProvider);
    final EventSortOrder sortOrder = ref.watch(eventSortOrderProvider);
    final Set<String> selected = EventSourceFilterRules.effectiveSelection(
      available: options,
      selected: filter.selectedKeys,
    );

    Future<void> setAll(bool value) async {
      final EventSourceFilterController notifier = ref.read(
        eventSourceFilterProvider.notifier,
      );
      for (final EventSourceOption option in options) {
        await notifier.setSelected(option.key, selected: value);
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
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
                  l10n.eventSourceFilterTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  TextButton(
                    onPressed: options.isEmpty ? null : () => setAll(true),
                    child: Text(l10n.eventSourceFilterSelectAll),
                  ),
                  TextButton(
                    onPressed: options.isEmpty ? null : () => setAll(false),
                    child: Text(l10n.eventSourceFilterDeselectAll),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final EventSourceOption option in options)
                      CheckboxListTile(
                        value: selected.contains(option.key),
                        title: Text(option.label),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (bool? value) => ref
                            .read(eventSourceFilterProvider.notifier)
                            .setSelected(option.key, selected: value ?? false),
                      ),
                    _EventSortSection(
                      value: sortOrder,
                      onChanged: (EventSortOrder order) => ref
                          .read(eventSortOrderProvider.notifier)
                          .setOrder(order),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.eventSourceFilterDone),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sortierung": one radio group, so a screen reader announces the two
/// options as mutually exclusive ("1 of 2, selected"). Each option is a full
/// list tile — well above the 48dp touch target — and says in text, not only
/// by the filled radio, what it does.
class _EventSortSection extends StatelessWidget {
  const _EventSortSection({required this.value, required this.onChanged});

  final EventSortOrder value;
  final ValueChanged<EventSortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              l10n.eventSortSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        RadioGroup<EventSortOrder>(
          groupValue: value,
          onChanged: (EventSortOrder? order) {
            if (order != null) onChanged(order);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RadioListTile<EventSortOrder>(
                value: EventSortOrder.chronological,
                title: Text(l10n.eventSortChronological),
                subtitle: Text(l10n.eventSortChronologicalHint),
              ),
              RadioListTile<EventSortOrder>(
                value: EventSortOrder.newestFirst,
                title: Text(l10n.eventSortNewestFirst),
                subtitle: Text(l10n.eventSortNewestFirstHint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
