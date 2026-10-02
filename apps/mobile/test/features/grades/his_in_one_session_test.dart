// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/grades/data/his_in_one_session.dart';
import 'package:campus_koethen/features/grades/domain/grade_portal_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_html_adapter.dart';

const String _baseUrl = 'https://sscportal.ssc.hs-anhalt.de';

bool _allows(Uri uri) =>
    gradePortalAllows(uri, scheme: 'https', host: 'sscportal.ssc.hs-anhalt.de');

void main() {
  test(
    'resolves a relative redirect against the current request URI',
    () async {
      final FakeHtmlAdapter adapter = FakeHtmlAdapter((RequestOptions options) {
        if (options.uri.path == '/qisserver/flow/start') {
          return const FakeHtmlResponse.redirect('next?step=2');
        }
        if (options.uri.path == '/qisserver/flow/next' &&
            options.uri.queryParameters['step'] == '2') {
          return const FakeHtmlResponse('<html>done</html>');
        }
        return const FakeHtmlResponse('wrong target', statusCode: 404);
      });
      final HisInOneSession session = HisInOneSession(
        baseUrl: _baseUrl,
        allows: _allows,
        adapter: adapter,
      );
      addTearDown(() => session.close('$_baseUrl/qisserver/logout'));

      final HisInOnePage page = await session.fetchPage(
        '$_baseUrl/qisserver/flow/start',
      );

      expect(page.url, '$_baseUrl/qisserver/flow/next?step=2');
      expect(page.html, '<html>done</html>');
    },
  );
}
