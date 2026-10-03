// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/core/network/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/validate_release_api.dart' as release_validator;

void main() {
  test('release validator decodes Flutter Dart defines', () {
    final String encoded = <String>[
      'OTHER=value',
      'API_BASE_URL=https://api.example.org',
    ].map((String value) => base64.encode(utf8.encode(value))).join(',');

    expect(release_validator.releaseApiConfigurationProblem(encoded), isNull);
  });

  test('release validator closes on absent and non-production origins', () {
    expect(
      release_validator.releaseApiConfigurationProblem(null),
      ApiConfigProblem.notConfigured,
    );

    final String loopback = base64.encode(
      utf8.encode('API_BASE_URL=http://localhost:3000'),
    );
    expect(
      release_validator.releaseApiConfigurationProblem(loopback),
      ApiConfigProblem.insecureScheme,
    );

    final String secureLoopback = base64.encode(
      utf8.encode('API_BASE_URL=https://localhost:3443'),
    );
    expect(
      release_validator.releaseApiConfigurationProblem(secureLoopback),
      ApiConfigProblem.malformed,
    );
  });

  test('Android release and profile builds depend on the validator', () {
    final String gradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(gradle, contains('validateDistributableApiConfiguration'));
    expect(gradle, contains('preReleaseBuild'));
    expect(gradle, contains('preProfileBuild'));
    expect(gradle, contains('tool/validate_release_api.dart'));
  });

  test('iOS release and profile builds run the same validator first', () {
    final String project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(project, contains('Validate API configuration'));
    expect(project, contains('tool/validate_release_api.dart'));
    expect(project, contains(r'$DART_DEFINES'));
  });
}
