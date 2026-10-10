// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachment_picker.dart';
import '../domain/attachment_store.dart';
import '../domain/request_store.dart';
import 'case_status_controller.dart';
import 'requests_controller.dart';
import 'requests_providers.dart';
import 'submissions_controller.dart';

/// Removes every trace the requests feature keeps on this device.
///
/// Both stores are always attempted, even if the first one fails: a partial
/// wipe that removed more is better than one that stopped at the first error.
/// What is not allowed is claiming success afterwards — the same rule the
/// grades wipe follows, and for the same reason: the bytes left behind are a
/// copy of a student ID and the status links that are the only access to the
/// submitted cases.
class RequestsLocalDataWiper {
  RequestsLocalDataWiper(this._ref);

  final Ref _ref;

  /// Returns true only when both stores confirmed they are gone.
  Future<bool> wipe() async {
    final RequestStore store = _ref.read(requestStoreProvider);
    final AttachmentStore attachments = _ref.read(attachmentStoreProvider);

    bool complete = true;
    try {
      complete = await attachments.wipeEverything() && complete;
    } catch (_) {
      complete = false;
    }
    try {
      complete = await store.wipeEverything() && complete;
    } catch (_) {
      complete = false;
    }

    // Drops the in-memory copies too. Without this the screens keep showing
    // drafts and cases whose bytes are already gone from disk — and the
    // loaded statuses would keep links, download URLs and personal data in
    // memory until the process ends (E-10). Fetches still running are
    // discarded by the status controller when they return.
    _ref.invalidate(requestsProvider);
    _ref.invalidate(submissionsProvider);
    _ref.invalidate(caseStatusProvider);
    // Rebuilt now rather than on its next read: a fetch returning after this
    // point must already see the new generation, or its own state read would
    // rebuild first and then write the old answer into the fresh state.
    _ref.read(caseStatusProvider);
    return complete;
  }
}

final Provider<RequestsLocalDataWiper> requestsLocalDataWiperProvider =
    Provider<RequestsLocalDataWiper>((Ref ref) => RequestsLocalDataWiper(ref));
