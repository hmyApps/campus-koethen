// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../events/domain/saved_event_snapshot.dart';

/// The saved events a notification may speak about: every bookmark except
/// the orphaned and the cancelled ones.
///
/// One rule for both categories that read bookmarks — the event reminder (N1)
/// and the daily overview (N2) — so they cannot disagree about what still
/// exists. An orphaned snapshot is one a successful load of its own source no
/// longer contained; announcing it, or counting it into a day, would be
/// announcing something that is gone. A cancelled one is not something to
/// look forward to.
///
/// Filtered on the snapshot itself rather than on the calendar entry it is
/// mapped to, so the rule holds regardless of which flags that mapping
/// carries over.
List<SavedEventSnapshot> notifiableSavedEvents(
  Iterable<SavedEventSnapshot> saved,
) => saved
    .where((SavedEventSnapshot s) => !s.isOrphaned && !s.isCancelled)
    .toList(growable: false);
