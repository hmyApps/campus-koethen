// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mail_failure.dart';
import '../domain/mail_folder.dart';
import 'mail_account_controller.dart';
import 'mail_providers.dart';
import 'mail_sync_controller.dart';

/// The mailbox currently being browsed. Defaults to the inbox and is switched
/// by the folder picker. The message list watches this and re-fetches on change.
class SelectedMailbox extends Notifier<MailFolder> {
  @override
  MailFolder build() {
    ref.watch(mailSessionGenerationProvider);
    return const MailFolder.inbox();
  }

  void select(MailFolder folder) => state = folder;
}

final NotifierProvider<SelectedMailbox, MailFolder> selectedMailboxProvider =
    NotifierProvider<SelectedMailbox, MailFolder>(SelectedMailbox.new);

/// All mailboxes on the server (IMAP LIST). Empty when signed out. No automatic
/// retry: a failure surfaces so the user can reopen the picker to try again.
final FutureProvider<List<MailFolder>> mailFoldersProvider =
    FutureProvider<List<MailFolder>>((Ref ref) async {
      ref.watch(mailSessionGenerationProvider);
      final MailAccountState? account = ref
          .watch(mailAccountControllerProvider)
          .value;
      if (account == null || !account.isSignedIn) {
        return const <MailFolder>[];
      }
      // No login with a password the server already refused; watched, so a
      // successful manual refresh makes the list loadable again.
      final MailFailure? rejected = ref.watch(mailCredentialsRejectionProvider);
      if (rejected != null) throw rejected;
      final credentials = await ref
          .read(mailAccountControllerProvider.notifier)
          .requireCredentials();
      return ref.read(mailGatewayProvider).fetchMailboxes(credentials);
    }, retry: (_, _) => null);
