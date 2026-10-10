// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one gate every HSA-GPT token mint has to pass (`AGENTS.md` §2).
///
/// HSA-GPT gets its own explicit consent screen instead of a checkbox in a
/// generic flow. Consent is therefore granted only for the duration of the
/// flow that showed that screen ([runWithConsent]) and the HSA-GPT adapter of
/// the university connector refuses to mint a token outside such a scope.
/// The connector itself opens a scope only to re-establish a link the user
/// had already consented to for the same account (a password-only change or
/// a rollback to the previous account), never to link a new account.
///
/// Deliberately in memory only: nothing here outlives the running flow.
class HsaKiConsentGate {
  int _openScopes = 0;

  bool get isGranted => _openScopes > 0;

  Future<T> runWithConsent<T>(Future<T> Function() body) async {
    _openScopes++;
    try {
      return await body();
    } finally {
      _openScopes--;
    }
  }
}

final Provider<HsaKiConsentGate> hsaKiConsentGateProvider =
    Provider<HsaKiConsentGate>((Ref ref) => HsaKiConsentGate());
