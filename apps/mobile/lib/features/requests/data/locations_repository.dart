// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:dio/dio.dart';

import '../domain/application_location.dart';
import '../domain/gremio_origin.dart';
import 'requests_api_config.dart';

/// The places an application can be addressed to.
///
/// Read straight from the receiving system, like the submission itself. The
/// list is not cached in the content cache: it is small, it changes rarely,
/// and a stale entry would route an application to a board that no longer
/// accepts it.
class LocationsRepository {
  LocationsRepository({required Dio dio, required String baseUrl})
    : this._(dio, RequestsApiConfig.stripTrailingSlash(baseUrl.trim()));

  LocationsRepository._(this._dio, this._baseUrl);

  final Dio _dio;
  final String _baseUrl;

  /// Returns the selectable locations.
  ///
  /// An empty list is a legitimate answer — the operator may have deactivated
  /// every location — and is not distinguishable from "nothing configured"
  /// here on purpose: both mean the user cannot pick one, and the UI says so
  /// once. Throwing on transport failure is left to the caller's `AsyncValue`.
  Future<List<ApplicationLocation>> fetch() async {
    // HTTPS or nothing (AGENTS.md §2): an `http://` value is "not
    // connected", exactly like an empty one — never a plaintext request.
    if (GremioOrigin.parse(_baseUrl) == null) {
      return const <ApplicationLocation>[];
    }

    final Response<dynamic> response = await _dio.get<dynamic>(
      '$_baseUrl${RequestsApiConfig.locationsPath}',
      options: Options(
        headers: <String, String>{'Accept': 'application/json'},
        receiveTimeout: RequestsApiConfig.receiveTimeout,
        // Only a 200 is an answer. Redirects are not followed on this client,
        // so a 3xx would otherwise arrive here as a body that is not a map and
        // read as "the operator deactivated everything" — a wrong statement
        // with no way to retry. Anything else throws and the caller's
        // AsyncValue offers the retry.
        validateStatus: (int? status) => status == 200,
      ),
    );

    final dynamic body = response.data;
    if (body is! Map<String, dynamic>) return const <ApplicationLocation>[];
    return ApplicationLocation.listFrom(body['locations']);
  }
}
