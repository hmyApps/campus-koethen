// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';
import '../../notifications/presentation/pre_permission_sheet.dart';
import '../application/saved_events_controller.dart';
import '../data/saved_events_store.dart';
import '../domain/saved_event_snapshot.dart';
import '../domain/unified_event.dart';

/// Shared bookmark action for an event in the event list and in the news feed.
class EventSaveButton extends ConsumerWidget {
  const EventSaveButton({required this.event, super.key});

  final UnifiedEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool saved = ref.watch(
      savedEventRefsProvider.select(
        (Set<String> refs) => refs.contains(event.eventRef),
      ),
    );
    final bool unavailable = ref.watch(
      savedEventsControllerProvider.select(
        (AsyncValue<List<SavedEventSnapshot>> value) =>
            value.isLoading || !value.hasValue,
      ),
    );
    final String tooltip = saved ? l10n.eventSaveRemove : l10n.eventSaveAdd;

    Future<void> toggle() async {
      final SavedEventsController controller = ref.read(
        savedEventsControllerProvider.notifier,
      );
      unawaited(HapticFeedback.selectionClick());
      try {
        if (saved) {
          await controller.remove(event.eventRef);
          return;
        }
        final bool accepted = await controller.save(event);
        if (!accepted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.eventSaveLimitReachedMessage)),
            );
          }
          return;
        }
        if (context.mounted) await maybeOfferNotificationOptIn(context, ref);
      } on SavedEventsStoreFailure {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.eventSaveFailedMessage)));
        }
      }
    }

    return Semantics(
      toggled: saved,
      label: tooltip,
      excludeSemantics: true,
      child: IconButton(
        tooltip: tooltip,
        onPressed: unavailable ? null : toggle,
        constraints: const BoxConstraints(
          minWidth: AppSizes.minTouchTarget,
          minHeight: AppSizes.minTouchTarget,
        ),
        isSelected: saved,
        icon: const Icon(AppIcons.bookmark_outlined),
        selectedIcon: const Icon(AppIcons.bookmark),
      ),
    );
  }
}
