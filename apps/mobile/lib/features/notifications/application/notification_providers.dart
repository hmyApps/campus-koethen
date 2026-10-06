// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/prefs/preference_keys.dart';
import '../../../core/prefs/settings_controller.dart';
import '../../../core/time/clock.dart';
import '../../../core/locale/locale_providers.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/device_time_zone.dart';
import '../data/local_notification_gateway.dart';
import '../domain/notification_category.dart';
import '../domain/notification_gateway.dart';
import '../domain/notification_permission.dart';
import '../domain/notification_plan.dart';
import '../domain/notification_preferences.dart';
import '../domain/notification_request.dart';
import 'canteen_favourite_candidates.dart';
import 'daily_summary_providers.dart';
import 'event_reminder_candidates.dart';
import 'grade_change_notification.dart';
import 'moodle_deadline_candidates.dart';
import 'notification_planner.dart';
import 'notification_scheduler.dart';
import 'notification_settings_controller.dart';

/// The platform gateway. Overridden in tests with a fake, and in `main()` with
/// nothing — the real one is the default so no start-up wiring can forget it.
final Provider<NotificationGateway> notificationGatewayProvider =
    Provider<NotificationGateway>((Ref ref) => LocalNotificationGateway());

final Provider<GradeChangeNotification> gradeChangeNotificationProvider =
    Provider<GradeChangeNotification>((Ref ref) {
      final AppLocalizations l10n = lookupAppLocalizations(
        ref.watch(activeLocaleProvider),
      );
      return GradeChangeNotification(
        gateway: ref.watch(notificationGatewayProvider),
        preferences: ref.watch(notificationSettingsProvider),
        permission:
            ref.watch(notificationPermissionProvider).value ??
            NotificationPermissionStatus.notDetermined,
        title: l10n.notificationGradeChangeTitle,
        body: l10n.notificationGradeChangeBody,
      );
    });

/// The device time zone resolver. Overridden in tests with
/// [FixedTimeZoneResolver].
final Provider<TimeZoneResolver> timeZoneResolverProvider =
    Provider<TimeZoneResolver>((Ref ref) => DeviceTimeZoneResolver());

/// The clock the planner reads "now" from.
final Provider<Clock> notificationClockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

/// The serialised scheduler.
final Provider<NotificationScheduler> notificationSchedulerProvider =
    Provider<NotificationScheduler>(
      (Ref ref) =>
          NotificationScheduler(ref.watch(notificationGatewayProvider)),
    );

/// **The extension point of the whole feature.**
///
/// Each approved category contributes its candidates here — LEVIORA-164
/// (daily summary), LEVIORA-165 (canteen favourites), LEVIORA-166
/// (event reminders) and the later Moodle-deadline extension each contribute
/// one provider and one line below. Immediate grade alerts deliberately bypass
/// the scheduled-candidate planner.
///
/// Two consequences worth being explicit about, because they are why this is
/// a provider rather than a function:
///
/// * **Re-planning needs no trigger list.** A candidate list that watches the
///   timetable cache, the canteen cache, the saved events box and the
///   preferences is rebuilt by Riverpod the moment any of them changes. Every
///   data-driven trigger of ADR-0001 § 7.1 — a successful fetch, a bookmark,
///   a favourite, a changed group or canteen — is covered by that alone. Only
///   the triggers that are *not* app state (foreground, time zone, day
///   change) need the coordinator.
/// * **The planner stays pure.** Providers end here. Below this line there is
///   a list of value objects and a function.
///
final Provider<List<NotificationRequest>> notificationCandidatesProvider =
    Provider<List<NotificationRequest>>(
      (Ref ref) => <NotificationRequest>[
        ...ref.watch(eventReminderCandidatesProvider),
        ...ref.watch(dailySummaryCandidatesProvider),
        ...ref.watch(canteenFavouriteCandidatesProvider),
        ...ref.watch(moodleDeadlineCandidatesProvider),
      ],
    );

/// The zone every wall-clock time is planned in.
///
/// Kept as a provider rather than resolved per run so that a zone change while
/// the app runs is a single invalidation — see `NotificationCoordinator`.
final FutureProvider<tz.Location> notificationLocationProvider =
    FutureProvider<tz.Location>(
      (Ref ref) => ref.watch(timeZoneResolverProvider).resolveLocation(),
    );

/// What the operating system currently allows.
///
/// Re-read on every resume: the permission can be withdrawn in the system
/// settings while the app is not running, and state 5 of the UX spec is
/// exactly that case.
final AsyncNotifierProvider<
  NotificationPermissionController,
  NotificationPermissionStatus
>
notificationPermissionProvider =
    AsyncNotifierProvider<
      NotificationPermissionController,
      NotificationPermissionStatus
    >(NotificationPermissionController.new);

/// Reads and changes the operating system permission.
class NotificationPermissionController
    extends AsyncNotifier<NotificationPermissionStatus> {
  @override
  Future<NotificationPermissionStatus> build() => _readStatus();

  Future<NotificationPermissionStatus> _readStatus() async {
    final NotificationPermissionStatus status = await ref
        .read(notificationGatewayProvider)
        .permissionStatus();
    final bool systemPromptRequested =
        ref
            .read(keyValueStoreProvider)
            .getInt(PreferenceKeys.notificationsSystemPromptRequested) ==
        1;
    // Darwin's notification API and Android 13's compatibility method can
    // both report only "disabled", not whether the first prompt has happened.
    // Until this installation records that request, disabled is still a
    // promptable fresh-install state rather than a confirmed refusal.
    if (status == NotificationPermissionStatus.denied &&
        !systemPromptRequested) {
      return NotificationPermissionStatus.notDetermined;
    }
    return status;
  }

  /// The status, freshly read.
  ///
  /// Not the cached value: a "not determined" from app start would show the
  /// pre-permission sheet to somebody who granted the permission in the
  /// system settings a minute ago.
  Future<NotificationPermissionStatus> currentStatus() async {
    await refresh();
    return state.value ?? NotificationPermissionStatus.notDetermined;
  }

  /// Re-reads the status without showing any dialog.
  Future<void> refresh() async {
    final NotificationPermissionStatus status = await _readStatus();
    state = AsyncData<NotificationPermissionStatus>(status);
  }

  /// Shows the operating system's dialog, once.
  ///
  /// Deliberately not guarded against a repeat call at this level — iOS itself
  /// answers a second request without showing anything, and hiding that
  /// behind an app-side flag would make the two platforms behave differently
  /// for no gain. What must not happen is the app *asking the reader again*,
  /// and that is a UI decision, made in the settings screen.
  Future<NotificationPermissionStatus> request() async {
    // Record the attempt before entering the system dialog. If the process is
    // killed while the dialog owns the screen, the OS has still consumed the
    // first request and a later launch must not pretend otherwise.
    await ref
        .read(keyValueStoreProvider)
        .setInt(PreferenceKeys.notificationsSystemPromptRequested, 1);
    final NotificationPermissionStatus status = await ref
        .read(notificationGatewayProvider)
        .requestPermission();
    state = AsyncData<NotificationPermissionStatus>(status);
    return status;
  }
}

/// The Android channels the reader has silenced. Always empty on iOS.
final FutureProvider<Set<NotificationCategory>>
mutedNotificationCategoriesProvider = FutureProvider<Set<NotificationCategory>>(
  (Ref ref) => ref.watch(notificationGatewayProvider).mutedCategories(),
);

/// The complete target state: what the operating system should be holding
/// right now.
///
/// Rebuilt whenever the candidates, the preferences, the permission or the
/// zone change — which is every trigger of ADR-0001 § 7.1 that is app state.
/// While the zone or the permission is still loading the plan is empty, so
/// nothing is ever scheduled against a guessed zone.
final Provider<NotificationPlan> notificationPlanProvider =
    Provider<NotificationPlan>((Ref ref) {
      final tz.Location? location = ref
          .watch(notificationLocationProvider)
          .value;
      final NotificationPermissionStatus? permission = ref
          .watch(notificationPermissionProvider)
          .value;
      if (location == null || permission == null) {
        return const NotificationPlan.empty();
      }
      final NotificationPreferences preferences = ref.watch(
        notificationSettingsProvider,
      );
      return planNotifications(
        candidates: ref.watch(notificationCandidatesProvider),
        preferences: preferences,
        permission: permission,
        now: tz.TZDateTime.from(
          ref.watch(notificationClockProvider).now(),
          location,
        ),
      );
    });
