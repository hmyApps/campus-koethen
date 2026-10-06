// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/nextcloud/domain/nextcloud_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const NextcloudProfile profile = NextcloudProfile();

  test('allows only the exact Hochschule Anhalt Nextcloud origin', () {
    expect(profile.allows(Uri.parse('https://cloud.hs-anhalt.de/')), isTrue);
    expect(
      profile.allows(Uri.parse('https://cloud.hs-anhalt.de:443/status.php')),
      isTrue,
    );
    expect(profile.allows(Uri.parse('http://cloud.hs-anhalt.de/')), isFalse);
    expect(
      profile.allows(Uri.parse('https://cloud.hs-anhalt.de:444/')),
      isFalse,
    );
    expect(
      profile.allows(Uri.parse('https://cloud.hs-anhalt.de.evil.test/')),
      isFalse,
    );
    expect(
      profile.allows(Uri.parse('https://user@cloud.hs-anhalt.de/')),
      isFalse,
    );
  });

  test('builds a DAV uri from encoded path segments only', () {
    expect(
      profile.davUri(userId: 'user name', path: '/Ordner/Übung 1.pdf'),
      Uri.parse(
        'https://cloud.hs-anhalt.de/remote.php/dav/files/'
        'user%20name/Ordner/%C3%9Cbung%201.pdf',
      ),
    );
  });

  test('rejects traversal and separator-bearing DAV segments', () {
    expect(
      () => profile.davUri(userId: 'student', path: '/../secret'),
      throwsArgumentError,
    );
    expect(
      () => profile.davUri(userId: 'student/other', path: '/Documents'),
      throwsArgumentError,
    );
  });

  test('accepts only pinned public share link shapes', () {
    expect(
      profile.allowsPublicShareUri(
        Uri.parse('https://cloud.hs-anhalt.de/s/share-token'),
      ),
      isTrue,
    );
    expect(
      profile.allowsPublicShareUri(
        Uri.parse('https://cloud.hs-anhalt.de/index.php/s/share-token'),
      ),
      isTrue,
    );
    expect(
      profile.allowsPublicShareUri(
        Uri.parse('https://cloud.hs-anhalt.de/s/share-token?download=1'),
      ),
      isFalse,
    );
    expect(
      profile.allowsPublicShareUri(
        Uri.parse('https://attacker.test/s/share-token'),
      ),
      isFalse,
    );
  });
}
