// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// The "GEANT TLS ECC 1" intermediate CA certificate, issued by HARICA
/// (Hellenic Academic and Research Institutions CA) — the one certificate
/// `ki.hs-anhalt.de` needs to complete its chain but does not itself send,
/// confirmed 2026-10-05 via:
///
/// ```sh
/// openssl s_client -connect ki.hs-anhalt.de:443 -servername ki.hs-anhalt.de -showcerts
/// ```
///
/// which returns only the leaf (`CN = ki.hs-anhalt.de`), `Verify return
/// code: 21 (unable to verify the first certificate)`. For comparison,
/// `moodle.hs-anhalt.de` and `mail.hs-anhalt.de` both send their complete
/// chain and verify cleanly (`return code: 0`) — this is a configuration gap
/// specific to the `ki.hs-anhalt.de` deployment, not a Hochschule-Anhalt-wide
/// or Campus-Köthen-side issue, and has been reported to HSA IT for a
/// server-side fix (adding the intermediate to their TLS certificate
/// bundle, as the other two hosts already do).
///
/// Desktop OSes and browsers paper over this by fetching the missing
/// intermediate automatically via the certificate's own Authority
/// Information Access (AIA) extension; `dart:io`'s TLS stack does not. This
/// constant is that same AIA-referenced certificate, fetched directly and
/// verified two independent ways before being embedded:
///
/// 1. Downloaded from the exact URL embedded in `ki.hs-anhalt.de`'s own leaf
///    certificate's `Authority Information Access` extension — HARICA's own
///    first-party repository: `http://crt.harica.gr/HARICA-GEANT-TLS-E1.cer`.
/// 2. Cross-checked against the Certificate Transparency log record for
///    "GEANT TLS ECC 1" (crt.sh id 16099180990) — identical SHA-256.
/// 3. Statically verified to complete a valid chain to the publicly trusted
///    HARICA TLS ECC Root CA 2021 (`openssl verify`, exit `OK`).
///
/// SHA-256 fingerprint:
/// `6C:DF:0B:A1:71:1E:85:6D:22:8B:A0:0C:A0:4C:5C:1C:3D:79:94:4C:03:7B:71:3B:15:5A:4E:E4:B4:7E:C5:3C`
/// Serial: `42:FD:DC:E1:26:16:07:E1:A5:E6:93:5A:40:01:61:DD`
/// Valid: 2025-01-03 – 2039-12-31.
///
/// This supplies only the one missing, already-publicly-trusted link in an
/// otherwise intact chain — it does not disable or weaken certificate
/// validation in any way, and is scoped to [HawkiSession]'s own HTTP client
/// only (see there). It becomes redundant, but stays harmless, once HSA
/// fixes the server configuration; at that point it may be removed.
const String geantTlsEcc1IntermediatePem = '''
-----BEGIN CERTIFICATE-----
MIIDNzCCArygAwIBAgIQQv3c4SYWB+Gl5pNaQAFh3TAKBggqhkjOPQQDAzBsMQsw
CQYDVQQGEwJHUjE3MDUGA1UECgwuSGVsbGVuaWMgQWNhZGVtaWMgYW5kIFJlc2Vh
cmNoIEluc3RpdHV0aW9ucyBDQTEkMCIGA1UEAwwbSEFSSUNBIFRMUyBFQ0MgUm9v
dCBDQSAyMDIxMB4XDTI1MDEwMzExMTQyMVoXDTM5MTIzMTExMTQyMFowYDELMAkG
A1UEBhMCR1IxNzA1BgNVBAoMLkhlbGxlbmljIEFjYWRlbWljIGFuZCBSZXNlYXJj
aCBJbnN0aXR1dGlvbnMgQ0ExGDAWBgNVBAMMD0dFQU5UIFRMUyBFQ0MgMTB2MBAG
ByqGSM49AgEGBSuBBAAiA2IABANPWLwh0Za2UqtbLV7/qNRm78zsttgSuvhn73bU
GtxETsVOEZeMUfMjgHw8EwrsSJI9oj0CgZQFFSEY1NJfcxA/NJiOYJUKPsFbpOrY
dr0q4g+aBZsXWeh7bMCzx24g/aOCAS0wggEpMBIGA1UdEwEB/wQIMAYBAf8CAQAw
HwYDVR0jBBgwFoAUyRtTgRL+BNUW0aq8mm+3oJUZbsowTQYIKwYBBQUHAQEEQTA/
MD0GCCsGAQUFBzAChjFodHRwOi8vY3J0LmhhcmljYS5nci9IQVJJQ0EtVExTLVJv
b3QtMjAyMS1FQ0MuY2VyMBEGA1UdIAQKMAgwBgYEVR0gADAdBgNVHSUEFjAUBggr
BgEFBQcDAgYIKwYBBQUHAwEwQgYDVR0fBDswOTA3oDWgM4YxaHR0cDovL2NybC5o
YXJpY2EuZ3IvSEFSSUNBLVRMUy1Sb290LTIwMjEtRUNDLmNybDAdBgNVHQ4EFgQU
6ZkGjRcfq/uWGlrIW15dXuzanI8wDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMD
A2kAMGYCMQD2M1caaY2OwmthgmANUQg3LBLI0/2LiCdxa2zNq0G59wVzbjEk0cR/
px52OegIwRACMQCk+iTmBlR6Xfv6igiiaFiPYfN2HfbcYLWbot5DZ2H1b4JVJV+V
rga7uu50SDG9hf4=
-----END CERTIFICATE-----
''';
