// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/mail/application/mail_sync_controller.dart';
import 'package:campus_koethen/features/notifications/application/new_mail_notification.dart';
import 'package:campus_koethen/features/notifications/domain/immediate_notification.dart';
import 'package:campus_koethen/features/notifications/domain/notification_category.dart';
import 'package:campus_koethen/features/notifications/domain/notification_request.dart';
import 'package:campus_koethen/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

MailNewMessageEvent _event({
  String id = '4711',
  int count = 1,
  String? sender = 'Demo Absender',
  String? subject = 'Demo-Betreff',
}) => MailNewMessageEvent(
  serial: 1,
  sessionGeneration: 1,
  newestMessageId: id,
  count: count,
  newestSender: sender,
  newestSubject: subject,
);

void main() {
  final AppLocalizations de = lookupAppLocalizations(const Locale('de'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  test('one new message shows its sender and subject, hidden on a locked '
      'screen where the platform allows', () {
    final ImmediateNotification n = buildNewMailNotification(
      l10n: de,
      event: _event(),
    )!;

    expect(n.title, 'Demo Absender');
    expect(n.body, 'Demo-Betreff');
    expect(n.category, NotificationCategory.newMail);
    expect(n.visibility, NotificationVisibility.neutral);
    expect(n.payload.target, '4711');
  });

  test('several new messages stay a plain count, without any content', () {
    final ImmediateNotification n = buildNewMailNotification(
      l10n: de,
      event: _event(count: 3),
    )!;

    expect(n.title, de.mailNewNotificationTitle);
    expect(n.body, de.mailNewNotificationBody(3));
    expect(n.body, isNot(contains('Demo')));
  });

  test('a message without a subject says so', () {
    final ImmediateNotification n = buildNewMailNotification(
      l10n: en,
      event: _event(subject: '  '),
    )!;

    expect(n.body, en.mailNewNotificationNoSubject);
  });

  test('a message without a known sender falls back to the plain text', () {
    final ImmediateNotification n = buildNewMailNotification(
      l10n: en,
      event: _event(sender: null),
    )!;

    expect(n.title, en.mailNewNotificationTitle);
    expect(n.body, en.mailNewNotificationBody(1));
  });

  test('long content is cut instead of filling the notification', () {
    final ImmediateNotification n = buildNewMailNotification(
      l10n: de,
      event: _event(sender: 'S' * 500, subject: 'B' * 500),
    )!;

    expect(n.title.length, lessThanOrEqualTo(80));
    expect(n.body.length, lessThanOrEqualTo(160));
  });

  test('control characters and line breaks never reach the notification', () {
    final ImmediateNotification n = buildNewMailNotification(
      l10n: de,
      event: _event(subject: 'Zeile\n\u0007eins'),
    )!;

    expect(n.body, 'Zeile eins');
  });

  test('an identifier that is not a plain UID produces nothing', () {
    expect(
      buildNewMailNotification(
        l10n: de,
        event: _event(id: '../x'),
      ),
      isNull,
    );
  });
}
