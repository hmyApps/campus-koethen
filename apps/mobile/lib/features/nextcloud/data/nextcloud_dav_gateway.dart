// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../../core/documents/app_document.dart';
import '../domain/nextcloud_account.dart';
import '../domain/nextcloud_entry.dart';
import '../domain/nextcloud_failure.dart';
import '../domain/nextcloud_gateway.dart';
import '../domain/nextcloud_profile.dart';

class NextcloudDavGateway implements NextcloudGateway {
  NextcloudDavGateway({
    required this._profile,
    Dio? dio,
    this.pollInterval = const Duration(seconds: 1),
    this.maxPollAttempts = 1200,
    this.loginTimeout = const Duration(minutes: 20),
  }) : _dio = dio ?? _defaultDio();

  final NextcloudProfile _profile;
  final Dio _dio;
  final Duration pollInterval;
  final int maxPollAttempts;
  final Duration loginTimeout;

  static Dio _defaultDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      validateStatus: (_) => true,
    ),
  );

  @override
  Future<NextcloudLoginStart> startLogin() async {
    try {
      final Response<Object?> response = await _dio.postUri<Object?>(
        _profile.loginFlowUri,
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const NextcloudFailure(NextcloudFailureKind.serviceUnavailable);
      }
      final Map<String, Object?> body = _objectMap(response.data);
      final Map<String, Object?> poll = _objectMap(body['poll']);
      final String token = _boundedString(poll['token'], max: 4096);
      final Uri pollUri = _strictUri(
        _boundedString(poll['endpoint'], max: 2048),
      );
      final Uri loginUri = _strictUri(_boundedString(body['login'], max: 2048));
      if (!_profile.allowsPollUri(pollUri) ||
          !_profile.allowsLoginUri(loginUri)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      return NextcloudLoginStart(
        loginUri: loginUri,
        pollUri: pollUri,
        pollToken: token,
      );
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDio(error);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
  }

  @override
  Future<NextcloudCredential> completeLogin(
    NextcloudLoginStart start, {
    required Future<void> canceled,
  }) async {
    if (!_profile.allowsPollUri(start.pollUri) ||
        !_validText(start.pollToken, 4096)) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    var wasCanceled = false;
    CancelToken? activePollToken;
    unawaited(
      canceled.then((_) {
        wasCanceled = true;
        activePollToken?.cancel('canceled');
      }),
    );
    final Stopwatch elapsed = Stopwatch()..start();

    try {
      for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
        if (elapsed.elapsed >= loginTimeout) {
          throw const NextcloudFailure(NextcloudFailureKind.loginTimedOut);
        }
        if (wasCanceled) {
          throw const NextcloudFailure(NextcloudFailureKind.canceled);
        }
        final CancelToken cancelToken = CancelToken();
        activePollToken = cancelToken;
        late final Response<Object?> response;
        try {
          response = await _dio.postUri<Object?>(
            start.pollUri,
            data: <String, String>{'token': start.pollToken},
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              responseType: ResponseType.json,
            ),
            cancelToken: cancelToken,
          );
        } finally {
          if (identical(activePollToken, cancelToken)) {
            activePollToken = null;
          }
        }
        if (wasCanceled) {
          throw const NextcloudFailure(NextcloudFailureKind.canceled);
        }
        if (response.statusCode == HttpStatus.notFound) {
          final bool canceledDuringDelay = await _delayOrCancel(canceled);
          if (canceledDuringDelay) {
            throw const NextcloudFailure(NextcloudFailureKind.canceled);
          }
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          throw const NextcloudFailure(NextcloudFailureKind.loginRejected);
        }
        final Map<String, Object?> body = _objectMap(response.data);
        final String server = _boundedString(body['server'], max: 2048);
        final String loginName = _boundedString(body['loginName'], max: 512);
        final String appPassword = _boundedString(
          body['appPassword'],
          max: 4096,
        );
        final NextcloudCredential issuedCredential = NextcloudCredential(
          server: NextcloudProfile.server.toString(),
          loginName: loginName,
          // Revocation authenticates with loginName and appPassword only. Use
          // a safe placeholder until OCS returns the canonical DAV uid.
          userId: 'pending-login',
          appPassword: appPassword,
        );
        try {
          final Uri serverUri = _strictUri(server);
          if (!_profile.allows(serverUri) ||
              (serverUri.path.isNotEmpty && serverUri.path != '/') ||
              serverUri.query.isNotEmpty ||
              serverUri.fragment.isNotEmpty) {
            throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
          }
          final String userId = await _fetchUserId(
            loginName: loginName,
            appPassword: appPassword,
            canceled: canceled,
          );
          _profile.davUri(userId: userId, path: '/');
          return NextcloudCredential(
            server: NextcloudProfile.server.toString(),
            loginName: loginName,
            userId: userId,
            appPassword: appPassword,
          );
        } catch (_) {
          await _revokeIgnoringFailure(issuedCredential);
          rethrow;
        }
      }
      throw const NextcloudFailure(NextcloudFailureKind.loginTimedOut);
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      if (wasCanceled || CancelToken.isCancel(error)) {
        throw const NextcloudFailure(NextcloudFailureKind.canceled);
      }
      throw _mapDio(error);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
  }

  Future<String> _fetchUserId({
    required String loginName,
    required String appPassword,
    required Future<void> canceled,
  }) async {
    final CancelToken cancelToken = CancelToken();
    unawaited(canceled.then((_) => cancelToken.cancel('canceled')));
    final Response<Object?> response = await _dio.getUri<Object?>(
      _profile.currentUserUri,
      options: Options(
        responseType: ResponseType.json,
        headers: _authorizedHeaders(loginName, appPassword),
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      throw const NextcloudFailure(NextcloudFailureKind.loginRejected);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw const NextcloudFailure(NextcloudFailureKind.serviceUnavailable);
    }
    final Map<String, Object?> ocs = _objectMap(
      _objectMap(response.data)['ocs'],
    );
    final Map<String, Object?> meta = _objectMap(ocs['meta']);
    if (meta['statuscode'] != 100 && meta['statuscode'] != 200) {
      throw const NextcloudFailure(NextcloudFailureKind.loginRejected);
    }
    return _boundedString(_objectMap(ocs['data'])['id'], max: 512);
  }

  @override
  Future<void> revoke(NextcloudCredential credential) async {
    _validateCredential(credential);
    try {
      final Response<Object?> response = await _dio.deleteUri<Object?>(
        _profile.revokeAppPasswordUri,
        options: Options(
          responseType: ResponseType.json,
          headers: _authorizedHeaders(
            credential.loginName,
            credential.appPassword,
          ),
        ),
      );
      final int status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw const NextcloudFailure(NextcloudFailureKind.serviceUnavailable);
      }
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDio(error);
    }
  }

  Future<void> _revokeIgnoringFailure(NextcloudCredential credential) async {
    try {
      await revoke(credential);
    } catch (_) {
      // The caller must still surface the original login/validation failure.
    }
  }

  @override
  Future<List<NextcloudEntry>> listFolder(
    NextcloudCredential credential,
    String path,
  ) async {
    _validateCredential(credential);
    late final Uri uri;
    late final List<String> requestedSegments;
    try {
      requestedSegments = _profile.normalizedSegments(path);
      uri = _profile.davUri(userId: credential.userId, path: path);
    } on ArgumentError {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    try {
      final Response<String> response = await _dio.requestUri<String>(
        uri,
        data: _propfindBody,
        options: Options(
          method: 'PROPFIND',
          responseType: ResponseType.plain,
          contentType: 'application/xml; charset=utf-8',
          headers: <String, Object?>{
            ..._authorizedHeaders(credential.loginName, credential.appPassword),
            'Depth': '1',
          },
        ),
      );
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const NextcloudFailure(NextcloudFailureKind.permissionDenied);
      }
      if (response.statusCode != HttpStatus.multiStatus) {
        throw const NextcloudFailure(NextcloudFailureKind.serviceUnavailable);
      }
      final String mediaType =
          response.headers
              .value(Headers.contentTypeHeader)
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          '';
      if (mediaType != 'application/xml' && mediaType != 'text/xml') {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final String body = response.data ?? '';
      if (body.length > _maxListingCharacters) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      if (_unsafeXmlDeclaration.hasMatch(body)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      return _parseListing(
        body,
        credential: credential,
        requestedSegments: requestedSegments,
      );
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDio(error);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
  }

  List<NextcloudEntry> _parseListing(
    String body, {
    required NextcloudCredential credential,
    required List<String> requestedSegments,
  }) {
    final XmlDocument document = XmlDocument.parse(body);
    final XmlElement root = document.rootElement;
    if (!_isDavElement(root, 'multistatus')) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    final List<XmlElement> responses = root.childElements
        .where((XmlElement element) => _isDavElement(element, 'response'))
        .toList(growable: false);
    if (responses.isEmpty || responses.length > _maxListingEntries) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }

    final List<NextcloudEntry> result = <NextcloudEntry>[];
    for (final XmlElement response in responses) {
      final String href = _directChildText(response, 'href', required: true)!;
      if (!_validText(href, 4096)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final Uri uri = NextcloudProfile.server.resolve(href);
      if (!_profile.allows(uri) ||
          uri.query.isNotEmpty ||
          uri.fragment.isNotEmpty) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final List<String> allSegments = uri.pathSegments.toList();
      // Collections are normally returned with a trailing slash. Dart may
      // represent that slash as one final empty path segment; no other empty
      // segment is valid inside the DAV hierarchy.
      if (allSegments.isNotEmpty && allSegments.last.isEmpty) {
        allSegments.removeLast();
      }
      if (allSegments.any((String segment) => segment.isEmpty)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final List<String> root = <String>[
        'remote.php',
        'dav',
        'files',
        credential.userId,
      ];
      if (allSegments.length < root.length || !_startsWith(allSegments, root)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final List<String> relative = allSegments.sublist(root.length);
      try {
        _profile.normalizedPath(relative);
      } on ArgumentError {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final List<XmlElement> properties = _successfulProperties(response);
      if (_listEquals(relative, requestedSegments)) continue;
      if (relative.length != requestedSegments.length + 1 ||
          !_startsWith(relative, requestedSegments)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }

      final bool isDirectory = properties.any(
        (XmlElement propertySet) => propertySet.descendants
            .whereType<XmlElement>()
            .any((XmlElement element) => _isDavElement(element, 'collection')),
      );
      final String fallbackName = relative.last;
      final String displayName =
          _propertyText(properties, 'displayname')?.trim() ?? fallbackName;
      final String name = displayName.isEmpty ? fallbackName : displayName;
      if (!_validText(name, 1024)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final String? sizeRaw = _propertyText(properties, 'getcontentlength');
      final int? size = sizeRaw == null ? null : int.tryParse(sizeRaw.trim());
      if (sizeRaw != null && (size == null || size < 0)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final String? modifiedRaw = _propertyText(properties, 'getlastmodified');
      final String? mediaTypeRaw = _propertyText(
        properties,
        'getcontenttype',
      )?.trim();
      if (mediaTypeRaw != null && !_validText(mediaTypeRaw, 512)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      result.add(
        NextcloudEntry(
          path: _profile.normalizedPath(relative),
          name: name,
          isDirectory: isDirectory,
          sizeBytes: isDirectory ? null : size,
          mediaType: isDirectory ? null : mediaTypeRaw,
          modifiedAt: _parseHttpDate(modifiedRaw),
        ),
      );
    }
    result.sort((NextcloudEntry a, NextcloudEntry b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List<NextcloudEntry>.unmodifiable(result);
  }

  @override
  Future<AppDocument> downloadFile(
    NextcloudCredential credential,
    NextcloudEntry entry, {
    NextcloudDownloadProgress? onProgress,
    Future<void>? canceled,
  }) async {
    _validateCredential(credential);
    if (entry.isDirectory ||
        (entry.sizeBytes != null &&
            entry.sizeBytes! > kMaxInMemoryPreviewBytes)) {
      throw const NextcloudFailure(NextcloudFailureKind.fileTooLarge);
    }
    late final Uri uri;
    try {
      uri = _profile.davUri(userId: credential.userId, path: entry.path);
    } on ArgumentError {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    final CancelToken cancelToken = CancelToken();
    var wasCanceled = false;
    if (canceled != null) {
      unawaited(
        canceled.then((_) {
          wasCanceled = true;
          cancelToken.cancel('canceled');
        }),
      );
    }
    try {
      final Response<ResponseBody> response = await _dio
          .requestUri<ResponseBody>(
            uri,
            options: Options(
              method: 'GET',
              responseType: ResponseType.stream,
              headers: _authorizedHeaders(
                credential.loginName,
                credential.appPassword,
              ),
            ),
            cancelToken: cancelToken,
          );
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const NextcloudFailure(NextcloudFailureKind.permissionDenied);
      }
      if (response.statusCode != HttpStatus.ok || response.data == null) {
        throw const NextcloudFailure(NextcloudFailureKind.downloadFailed);
      }
      final String? declaredLengthRaw = response.headers.value(
        Headers.contentLengthHeader,
      );
      final int? declaredLength = declaredLengthRaw == null
          ? null
          : int.tryParse(declaredLengthRaw.trim());
      if (declaredLengthRaw != null &&
          (declaredLength == null || declaredLength < 0)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      if (declaredLength != null && declaredLength > kMaxInMemoryPreviewBytes) {
        throw const NextcloudFailure(NextcloudFailureKind.fileTooLarge);
      }
      final int? progressTotal = declaredLength ?? entry.sizeBytes;
      final BytesBuilder bytes = BytesBuilder(copy: false);
      var received = 0;
      onProgress?.call(received, progressTotal);
      await for (final Uint8List chunk in response.data!.stream) {
        if (wasCanceled) {
          throw const NextcloudFailure(NextcloudFailureKind.canceled);
        }
        received += chunk.length;
        if (received > kMaxInMemoryPreviewBytes) {
          throw const NextcloudFailure(NextcloudFailureKind.fileTooLarge);
        }
        bytes.add(chunk);
        onProgress?.call(received, progressTotal);
      }
      final String filename = safeDocumentFilename(entry.name);
      return AppDocument(
        filename: filename,
        mediaType: mediaTypeFor(
          filename,
          declared:
              response.headers.value(Headers.contentTypeHeader) ??
              entry.mediaType,
        ),
        bytes: bytes.takeBytes(),
        sizeBytes: received,
      );
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      if (wasCanceled || CancelToken.isCancel(error)) {
        throw const NextcloudFailure(NextcloudFailureKind.canceled);
      }
      throw _mapDio(error, download: true);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.downloadFailed);
    }
  }

  @override
  Future<void> uploadFile(
    NextcloudCredential credential, {
    required String directoryPath,
    required NextcloudUploadFile file,
    NextcloudUploadProgress? onProgress,
    Future<void>? canceled,
  }) async {
    _validateCredential(credential);
    if (file.length < 0 ||
        !_validText(file.filename, 1024) ||
        !_validText(file.mediaType, 512)) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidFileName);
    }
    late final Uri uri;
    try {
      final List<String> directory = _profile.normalizedSegments(directoryPath);
      final List<String> filename = _profile.normalizedSegments(
        '/${file.filename}',
      );
      if (filename.length != 1) throw const FormatException();
      uri = _profile.davUri(
        userId: credential.userId,
        path: _profile.normalizedPath(<String>[...directory, ...filename]),
      );
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidFileName);
    }
    final CancelToken cancelToken = CancelToken();
    var wasCanceled = false;
    if (canceled != null) {
      unawaited(
        canceled.then((_) {
          wasCanceled = true;
          cancelToken.cancel('canceled');
        }),
      );
    }
    try {
      final Response<Object?> response = await _dio.requestUri<Object?>(
        uri,
        data: file.openRead(),
        options: Options(
          method: 'PUT',
          responseType: ResponseType.plain,
          contentType: file.mediaType,
          sendTimeout: const Duration(minutes: 10),
          followRedirects: false,
          headers: <String, Object?>{
            ..._authorizedHeaders(credential.loginName, credential.appPassword),
            Headers.contentLengthHeader: file.length,
            'If-None-Match': '*',
          },
        ),
        cancelToken: cancelToken,
        onSendProgress: (int sent, int total) {
          if (!wasCanceled) onProgress?.call(sent, file.length);
        },
      );
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const NextcloudFailure(NextcloudFailureKind.permissionDenied);
      }
      if (response.statusCode == HttpStatus.preconditionFailed) {
        throw const NextcloudFailure(NextcloudFailureKind.alreadyExists);
      }
      if (!_successfulMutationStatus(response.statusCode)) {
        throw const NextcloudFailure(NextcloudFailureKind.uploadFailed);
      }
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      if (wasCanceled || CancelToken.isCancel(error)) {
        throw const NextcloudFailure(NextcloudFailureKind.canceled);
      }
      throw _mapDio(error, mutation: NextcloudFailureKind.uploadFailed);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.uploadFailed);
    }
  }

  @override
  Future<void> deleteEntry(
    NextcloudCredential credential,
    NextcloudEntry entry,
  ) async {
    _validateCredential(credential);
    late final Uri uri;
    try {
      if (_profile.normalizedSegments(entry.path).isEmpty) {
        throw const FormatException();
      }
      uri = _profile.davUri(userId: credential.userId, path: entry.path);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    try {
      final Response<Object?> response = await _dio.deleteUri<Object?>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: _authorizedHeaders(
            credential.loginName,
            credential.appPassword,
          ),
        ),
      );
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const NextcloudFailure(NextcloudFailureKind.permissionDenied);
      }
      if (!_successfulMutationStatus(response.statusCode)) {
        throw const NextcloudFailure(NextcloudFailureKind.deleteFailed);
      }
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDio(error, mutation: NextcloudFailureKind.deleteFailed);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.deleteFailed);
    }
  }

  @override
  Future<Uri> createPublicShare(
    NextcloudCredential credential,
    NextcloudEntry entry,
  ) async {
    _validateCredential(credential);
    try {
      if (_profile.normalizedSegments(entry.path).isEmpty) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      final Response<Object?> response = await _dio.postUri<Object?>(
        _profile.sharesUri,
        data: <String, String>{
          'path': entry.path,
          'shareType': '3',
          'permissions': '1',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          followRedirects: false,
          headers: _authorizedHeaders(
            credential.loginName,
            credential.appPassword,
          ),
        ),
      );
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const NextcloudFailure(NextcloudFailureKind.permissionDenied);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const NextcloudFailure(NextcloudFailureKind.shareFailed);
      }
      final Map<String, Object?> ocs = _objectMap(
        _objectMap(response.data)['ocs'],
      );
      final Object? statusCode = _objectMap(ocs['meta'])['statuscode'];
      if (statusCode != 100 && statusCode != 200) {
        throw const NextcloudFailure(NextcloudFailureKind.shareFailed);
      }
      final Uri link = _strictUri(
        _boundedString(_objectMap(ocs['data'])['url'], max: 2048),
      );
      if (!_profile.allowsPublicShareUri(link)) {
        throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
      }
      return link;
    } on NextcloudFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDio(error, mutation: NextcloudFailureKind.shareFailed);
    } on ArgumentError {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    } catch (_) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
  }

  Map<String, String> _authorizedHeaders(String username, String password) =>
      <String, String>{
        'authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'OCS-APIRequest': 'true',
      };

  void _validateCredential(NextcloudCredential credential) {
    final Uri? server = Uri.tryParse(credential.server);
    if (server == null ||
        !_profile.allows(server) ||
        (server.path.isNotEmpty && server.path != '/') ||
        server.query.isNotEmpty ||
        server.fragment.isNotEmpty ||
        !_validText(credential.loginName, 512) ||
        !_validText(credential.userId, 512) ||
        !_validText(credential.appPassword, 4096)) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    try {
      _profile.davUri(userId: credential.userId, path: '/');
    } on ArgumentError {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
  }

  Future<bool> _delayOrCancel(Future<void> canceled) =>
      Future.any(<Future<bool>>[
        Future<void>.delayed(pollInterval).then((_) => false),
        canceled.then((_) => true),
      ]);

  NextcloudFailure _mapDio(
    DioException error, {
    bool download = false,
    NextcloudFailureKind? mutation,
  }) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const NextcloudFailure(NextcloudFailureKind.timeout);
    }
    if (error.type == DioExceptionType.badCertificate ||
        error.error is HandshakeException ||
        error.error is CertificateException) {
      return const NextcloudFailure(NextcloudFailureKind.tlsOrHostRejected);
    }
    if (error.type == DioExceptionType.connectionError) {
      return const NextcloudFailure(NextcloudFailureKind.networkUnavailable);
    }
    return NextcloudFailure(
      mutation ??
          (download
              ? NextcloudFailureKind.downloadFailed
              : NextcloudFailureKind.serviceUnavailable),
    );
  }
}

bool _successfulMutationStatus(int? status) =>
    status == HttpStatus.ok ||
    status == HttpStatus.created ||
    status == HttpStatus.noContent;

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _boundedString(Object? value, {required int max}) {
  if (value is! String || !_validText(value, max)) {
    throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
  }
  return value;
}

Uri _strictUri(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null || !uri.isAbsolute) {
    throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
  }
  return uri;
}

bool _validText(String value, int maxLength) =>
    value.isNotEmpty &&
    value.length <= maxLength &&
    !_controlCharacters.hasMatch(value);

String? _directChildText(
  XmlElement parent,
  String localName, {
  bool required = false,
}) {
  final Iterable<XmlElement> matches = parent.childElements.where(
    (XmlElement element) => _isDavElement(element, localName),
  );
  if (matches.isEmpty) {
    if (required) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    return null;
  }
  if (matches.length != 1) {
    throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
  }
  return matches.first.innerText;
}

List<XmlElement> _successfulProperties(XmlElement response) {
  final List<XmlElement> properties = <XmlElement>[];
  for (final XmlElement propstat in response.childElements.where(
    (XmlElement element) => _isDavElement(element, 'propstat'),
  )) {
    final String? status = _directChildText(propstat, 'status');
    if (status == null || !_successfulPropstat.hasMatch(status.trim())) {
      continue;
    }
    final Iterable<XmlElement> matches = propstat.childElements.where(
      (XmlElement element) => _isDavElement(element, 'prop'),
    );
    if (matches.isEmpty) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    properties.add(matches.first);
  }
  if (properties.isEmpty) {
    throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
  }
  return properties;
}

bool _isDavElement(XmlElement element, String localName) =>
    element.name.local == localName &&
    element.name.namespaceUri == _davNamespace;

String? _propertyText(List<XmlElement> properties, String localName) {
  for (final XmlElement propertySet in properties) {
    final String? value = _directChildText(propertySet, localName);
    if (value != null) return value;
  }
  return null;
}

DateTime? _parseHttpDate(String? value) {
  if (value == null) return null;
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
  }
  try {
    return HttpDate.parse(normalized).toUtc();
  } catch (_) {
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      throw const NextcloudFailure(NextcloudFailureKind.invalidResponse);
    }
    return parsed.toUtc();
  }
}

bool _startsWith(List<String> value, List<String> prefix) {
  if (value.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (value[index] != prefix[index]) return false;
  }
  return true;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

const int _maxListingCharacters = 4 * 1024 * 1024;
const int _maxListingEntries = 10000;
const String _davNamespace = 'DAV:';
final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
final RegExp _unsafeXmlDeclaration = RegExp(
  r'<!\s*(?:DOCTYPE|ENTITY)\b',
  caseSensitive: false,
);
final RegExp _successfulPropstat = RegExp(
  r'^HTTP/\d(?:\.\d)?\s+200(?:\s|$)',
  caseSensitive: false,
);

const String _propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getcontenttype/>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>''';
