// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Exact network boundary for the Hochschule Anhalt KI agent (HAWKI,
/// branded "HSA-GPT"), confirmed 2026-10-04 against the real, currently
/// deployed instance.
///
/// `ki.hs-anhalt.de` is HSA's own stated successor to `gpt.hs-anhalt.de`
/// (which HSA has announced it will retire end of May 2026); only the new
/// host is pinned here, matching AGENTS.md's "exakte Origin" requirement —
/// there is no fallback to the old host.
class HsaKiProfile {
  const HsaKiProfile();

  static const String host = 'ki.hs-anhalt.de';
  static final Uri server = Uri.parse('https://$host');

  Uri get loginPageUri => server.resolve('/login');
  Uri get loginUri => server.resolve('/req/login');
  Uri get createTokenUri => server.resolve('/req/profile/create-token');
  Uri get revokeTokenUri => server.resolve('/req/profile/revoke-token');
  Uri get logoutUri => server.resolve('/logout');
  // Confirmed 2026-10-06 against the real, currently deployed instance:
  // unlike `ai-models` (a JSON:API resource, genuinely under `/hawki/v1`),
  // `ai-req` is registered without that prefix — `/api/hawki/v1/ai-req`
  // 404s for real (Laravel's own "route … could not be found"), while
  // `/api/ai-req` answers 401 Unauthenticated, proving the route exists
  // there. Source: `routes/api.php`, the `ai-req` group has no `->prefix()`
  // call, only the framework's automatic `/api` prefix applies.
  Uri get aiRequestUri => server.resolve('/api/ai-req');
  Uri get aiModelsUri => server.resolve('/api/hawki/v1/ai-models');

  bool allows(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == host &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;
}
