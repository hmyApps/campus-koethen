// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../domain/hsa_mail_profile.dart';
import '../domain/mail_cache_store.dart';
import '../domain/mail_credentials.dart';
import '../domain/mail_directory_gateway.dart';
import '../domain/mail_failure.dart';

/// Minimal EWS `ResolveNames` client for the pinned university Exchange host.
/// No autodiscovery, redirects, cookies or arbitrary EWS operations exist at
/// this boundary.
class ExchangeDirectoryGateway implements MailDirectoryGateway {
  ExchangeDirectoryGateway(
    this._profile, {
    Dio? dio,
    Duration timeout = const Duration(seconds: 15),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: timeout,
               sendTimeout: timeout,
               receiveTimeout: timeout,
               responseType: ResponseType.plain,
               followRedirects: false,
             ),
           );

  final HsaMailProfile _profile;
  final Dio _dio;

  @override
  Future<List<MailAddressEntry>> search(
    MailCredentials credentials,
    String query, {
    int limit = 20,
  }) async {
    final String needle = query.trim();
    if (needle.length < 2) return const <MailAddressEntry>[];
    if (needle.length > 100 || limit < 1 || limit > 100) {
      throw const MailFailure(MailFailureKind.protocol);
    }

    try {
      final Response<String> response = await _dio.postUri<String>(
        _profile.ewsUri,
        data: _requestXml(needle),
        options: Options(
          responseType: ResponseType.plain,
          contentType: 'text/xml; charset=utf-8',
          followRedirects: false,
          validateStatus: (int? status) => status != null,
          headers: <String, String>{
            'authorization':
                'Basic ${base64Encode(utf8.encode('${credentials.emailAddress}:${credentials.password}'))}',
            'SOAPAction':
                'http://schemas.microsoft.com/exchange/services/2006/messages/ResolveNames',
          },
        ),
      );
      final int status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        throw const MailFailure(MailFailureKind.invalidCredentials);
      }
      if (status >= 500) {
        throw const MailFailure(MailFailureKind.serverUnreachable);
      }
      if (status != 200 || response.data == null) {
        throw const MailFailure(MailFailureKind.protocol);
      }
      return _parse(response.data!, limit: limit);
    } on MailFailure {
      rethrow;
    } on DioException catch (error) {
      throw MailFailure(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.transformTimeout => MailFailureKind.timeout,
        DioExceptionType.badCertificate => MailFailureKind.tls,
        DioExceptionType.connectionError => MailFailureKind.serverUnreachable,
        _ => MailFailureKind.network,
      });
    } catch (_) {
      // XML and all other raw failures are collapsed so response bodies and
      // credentials can never escape into UI state or logs.
      throw const MailFailure(MailFailureKind.protocol);
    }
  }

  static String _requestXml(String query) {
    final XmlBuilder builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element(
      'soap:Envelope',
      namespaces: <String, String>{
        'soap': 'http://schemas.xmlsoap.org/soap/envelope/',
        't': 'http://schemas.microsoft.com/exchange/services/2006/types',
        'm': 'http://schemas.microsoft.com/exchange/services/2006/messages',
      },
      nest: () {
        builder.element(
          'soap:Header',
          nest: () {
            builder.element(
              't:RequestServerVersion',
              attributes: <String, String>{'Version': 'Exchange2016'},
            );
          },
        );
        builder.element(
          'soap:Body',
          nest: () {
            builder.element(
              'm:ResolveNames',
              attributes: <String, String>{
                'ReturnFullContactData': 'false',
                'SearchScope': 'ContactsActiveDirectory',
              },
              nest: () => builder.element('m:UnresolvedEntry', nest: query),
            );
          },
        );
      },
    );
    return builder.buildDocument().toXmlString();
  }

  static List<MailAddressEntry> _parse(String raw, {required int limit}) {
    final XmlDocument document = XmlDocument.parse(raw);
    final Set<String> responseCodes = document.descendants
        .whereType<XmlElement>()
        .where((XmlElement element) => element.name.local == 'ResponseCode')
        .map((XmlElement element) => element.innerText.trim())
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (responseCodes.isEmpty ||
        responseCodes.any(
          (String code) =>
              code != 'NoError' &&
              code != 'ErrorNameResolutionMultipleResults' &&
              code != 'ErrorNameResolutionNoResults',
        )) {
      throw const MailFailure(MailFailureKind.protocol);
    }
    final bool noResults = responseCodes.contains(
      'ErrorNameResolutionNoResults',
    );
    final Map<String, MailAddressEntry> distinct = <String, MailAddressEntry>{};
    for (final XmlElement resolution
        in document.descendants.whereType<XmlElement>().where(
          (XmlElement element) => element.name.local == 'Resolution',
        )) {
      final XmlElement? mailbox = resolution.childElements
          .where((XmlElement element) => element.name.local == 'Mailbox')
          .firstOrNull;
      if (mailbox == null) continue;
      String value(String name) =>
          mailbox.childElements
              .where((XmlElement element) => element.name.local == name)
              .map((XmlElement element) => element.innerText.trim())
              .firstOrNull ??
          '';
      final String email = value('EmailAddress');
      if (!isValidEmailAddress(email)) continue;
      final String name = value('Name');
      distinct.putIfAbsent(
        email.toLowerCase(),
        () => MailAddressEntry(email: email, name: name.isEmpty ? null : name),
      );
      if (distinct.length >= limit) break;
    }
    if (distinct.isEmpty && !noResults) {
      throw const MailFailure(MailFailureKind.protocol);
    }
    return List<MailAddressEntry>.unmodifiable(distinct.values);
  }
}
