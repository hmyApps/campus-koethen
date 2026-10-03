// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';
import 'dart:io';

import 'package:campus_koethen/core/network/api_config.dart';

/// Validates the base URL embedded by Flutter's comma-separated, base64 Dart
/// defines. Distributable builds never permit the local HTTP exception.
ApiConfigProblem? releaseApiConfigurationProblem(String? dartDefines) {
  if (dartDefines == null || dartDefines.isEmpty) {
    return ApiConfigProblem.notConfigured;
  }

  String? baseUrl;
  try {
    for (final String encoded in dartDefines.split(',')) {
      if (encoded.isEmpty) continue;
      final String decoded = utf8.decode(base64.decode(encoded));
      final int separator = decoded.indexOf('=');
      if (separator <= 0) return ApiConfigProblem.malformed;
      if (decoded.substring(0, separator) != 'API_BASE_URL') continue;
      if (baseUrl != null) return ApiConfigProblem.malformed;
      baseUrl = decoded.substring(separator + 1);
    }
  } on FormatException {
    return ApiConfigProblem.malformed;
  }

  return ApiConfig.validateBaseUrl(
    baseUrl ?? '',
    isExplicitlyConfigured: baseUrl != null,
    allowLoopback: false,
  );
}

ApiConfigProblem? _directApiConfigurationProblem(String? baseUrl) =>
    ApiConfig.validateBaseUrl(
      baseUrl ?? '',
      isExplicitlyConfigured: baseUrl != null,
      allowLoopback: false,
    );

void main(List<String> arguments) {
  final List<String> dartDefineArguments = arguments
      .where((String value) => value.startsWith('--dart-defines='))
      .toList(growable: false);
  final List<String> directArguments = arguments
      .where((String value) => value.startsWith('--api-base-url='))
      .toList(growable: false);

  if (arguments.length != 1 ||
      dartDefineArguments.length + directArguments.length != 1) {
    stderr.writeln(
      'Expected exactly one --dart-defines=… or --api-base-url=… argument.',
    );
    exitCode = 64;
    return;
  }

  final ApiConfigProblem? problem;
  if (dartDefineArguments.isNotEmpty) {
    problem = releaseApiConfigurationProblem(
      dartDefineArguments.single.substring('--dart-defines='.length),
    );
  } else {
    problem = _directApiConfigurationProblem(
      directArguments.single.substring('--api-base-url='.length),
    );
  }

  if (problem != null) {
    stderr.writeln(
      'Distributable builds require API_BASE_URL to be one exact HTTPS origin '
      '(no credentials, path, query, fragment, or loopback address).',
    );
    stderr.writeln('Configuration rejected: ${problem.name}.');
    exitCode = 78;
    return;
  }

  stdout.writeln('Campus API release origin is valid.');
}
