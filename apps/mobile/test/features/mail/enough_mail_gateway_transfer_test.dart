// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/features/mail/data/enough_mail_gateway.dart';
import 'package:campus_koethen/features/mail/domain/hsa_mail_profile.dart';
import 'package:campus_koethen/features/mail/domain/mail_credentials.dart';
import 'package:campus_koethen/features/mail/domain/mail_failure.dart';
import 'package:campus_koethen/features/mail/domain/mail_message.dart';
import 'package:enough_mail/enough_mail.dart' show AuthMechanism, SmtpClient;
import 'package:enough_mail/enough_mail.dart' show SmtpResponse;
import 'package:flutter_test/flutter_test.dart';

/// Points the gateway at loopback fakes instead of `mail.hs-anhalt.de`.
class _LoopbackMailProfile extends HsaMailProfile {
  const _LoopbackMailProfile({this.imap = 1, this.smtp = 1});

  final int imap;
  final int smtp;

  @override
  String get imapHost => '127.0.0.1';

  @override
  int get imapPort => imap;

  @override
  bool get imapImplicitTls => false;

  @override
  String get smtpHost => '127.0.0.1';

  @override
  int get smtpPort => smtp;
}

/// The loopback SMTP fake speaks plain TCP, so the TLS upgrade and the
/// authentication exchange are skipped here. Everything else — EHLO, the
/// envelope, DATA and QUIT — runs over a real socket.
class _PlainSmtpClient extends SmtpClient {
  _PlainSmtpClient() : super('campus-koethen.localhost');

  @override
  Future<SmtpResponse> startTls() async =>
      SmtpResponse(<String>['220 ready to start TLS']);

  @override
  Future<SmtpResponse> authenticate(
    String name,
    String password, [
    AuthMechanism authMechanism = AuthMechanism.plain,
  ]) async => SmtpResponse(<String>['235 authenticated']);
}

/// A minimal SMTP server that accepts the envelope and the message data but
/// never confirms the end of DATA — a submission stalled after the server may
/// already have taken the message.
class _StallingSmtpServer {
  _StallingSmtpServer._(this._server) {
    _server.listen(_handle);
  }

  final ServerSocket _server;
  final List<String> commands = <String>[];
  final Completer<void> closedByClient = Completer<void>();

  static Future<_StallingSmtpServer> start() async => _StallingSmtpServer._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  int get port => _server.port;

  void _handle(Socket socket) {
    socket.write('220 fake ESMTP ready\r\n');
    bool inData = false;
    String pending = '';
    socket.listen(
      (List<int> data) {
        pending += utf8.decode(data, allowMalformed: true);
        int index;
        while ((index = pending.indexOf('\r\n')) != -1) {
          final String line = pending.substring(0, index);
          pending = pending.substring(index + 2);
          if (inData) {
            if (line == '.') commands.add('<end of data>');
            continue; // never answers the end of DATA
          }
          commands.add(line);
          final String upper = line.toUpperCase();
          if (upper.startsWith('EHLO')) {
            socket.write('250-fake\r\n250-STARTTLS\r\n250 8BITMIME\r\n');
          } else if (upper.startsWith('MAIL FROM') ||
              upper.startsWith('RCPT TO')) {
            socket.write('250 ok\r\n');
          } else if (upper == 'DATA') {
            inData = true;
            socket.write('354 go ahead\r\n');
          } else if (upper == 'QUIT') {
            socket.write('221 bye\r\n');
          } else {
            socket.write('250 ok\r\n');
          }
        }
      },
      onDone: () {
        if (!closedByClient.isCompleted) closedByClient.complete();
      },
      onError: (Object _) {},
    );
  }

  Future<void> close() => _server.close();
}

const MailCredentials _credentials = MailCredentials(
  emailAddress: 'stud@hs-anhalt.de',
  password: 'pw',
);

void main() {
  group('EnoughMailGateway.send', () {
    test('a submission that stalls after DATA ends with "outcome unknown", '
        'closes the socket and never retries', () async {
      final _StallingSmtpServer server = await _StallingSmtpServer.start();
      addTearDown(server.close);
      final EnoughMailGateway gateway = EnoughMailGateway(
        _LoopbackMailProfile(smtp: server.port),
        commandTimeout: const Duration(milliseconds: 300),
        cleanupTimeout: const Duration(milliseconds: 50),
        minTransferBytesPerSecond: 1 << 30,
        smtpClientFactory: _PlainSmtpClient.new,
      );

      await expectLater(
        gateway.send(
          _credentials,
          const OutgoingMessage(
            to: <String>['empfang@hs-anhalt.de'],
            subject: 'Demo',
            text: 'Demo-Inhalt',
          ),
        ),
        throwsA(
          isA<MailFailure>().having(
            (MailFailure failure) => failure.kind,
            'kind',
            MailFailureKind.sendOutcomeUnknown,
          ),
        ),
      );

      await server.closedByClient.future.timeout(const Duration(seconds: 2));
      expect(server.commands, contains('<end of data>'));
      expect(server.commands, isNot(contains('QUIT')));
      expect(
        server.commands.where((String c) => c.toUpperCase() == 'DATA'),
        hasLength(1),
        reason: 'no automatic second submission',
      );
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
