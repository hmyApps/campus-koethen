// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import '../../../l10n/l10n.dart';
import '../../mail/application/mail_sync_controller.dart';
import '../domain/immediate_notification.dart';
import '../domain/notification_category.dart';
import '../domain/notification_payload.dart';
import '../domain/notification_request.dart';

const int _maxSenderLength = 60;
const int _maxSubjectLength = 120;

/// The local notification for freshly arrived mail, or `null` for an event
/// that must not produce one.
///
/// One new message shows its sender and subject: the text is built on the
/// device from the already cached header and handed straight to the local
/// notification, never to a server. Several messages stay a plain count — a
/// list of subjects would only fill the lock screen. The platform's
/// "private" visibility keeps the text off a locked Android screen; iOS has
/// no such per-notification flag, which `docs/notifications.md` says openly.
ImmediateNotification? buildNewMailNotification({
  required AppLocalizations l10n,
  required MailNewMessageEvent event,
}) {
  // The identifier is the IMAP UID and ends up in the tap payload.
  if (!RegExp(r'^\d{1,20}$').hasMatch(event.newestMessageId)) return null;

  final String sender = _clean(event.newestSender ?? '', _maxSenderLength);
  final bool showsContent = event.count == 1 && sender.isNotEmpty;
  final String subject = _clean(event.newestSubject ?? '', _maxSubjectLength);

  return ImmediateNotification(
    key: '${NotificationCategory.newMail.keyPrefix}:${event.newestMessageId}',
    category: NotificationCategory.newMail,
    title: showsContent ? sender : l10n.mailNewNotificationTitle,
    body: showsContent
        ? (subject.isEmpty ? l10n.mailNewNotificationNoSubject : subject)
        : l10n.mailNewNotificationBody(event.count),
    payload: NotificationPayload(
      category: NotificationCategory.newMail,
      target: event.newestMessageId,
    ),
    visibility: NotificationVisibility.neutral,
  );
}

/// One line without control characters, cut to [limit].
String _clean(String value, int limit) {
  final String oneLine = value
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (oneLine.length <= limit) return oneLine;
  return '${oneLine.substring(0, limit - 1).trimRight()}…';
}
