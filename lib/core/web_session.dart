import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'uploads.dart';
import 'session_vault.dart';

import 'package:html/parser.dart' as html;

/// The buyer backend currently exposes Laravel web sessions and Inertia pages.
/// Optional persistence uses the native secure store; credentials are never saved.
class WebSession {
  WebSession(this.origin, {HttpClient? client, this._vault})
    : _client = client ?? HttpClient() {
    if (!['http', 'https'].contains(origin.scheme) ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.path != '/' && origin.path.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw ArgumentError('BAGOO_BASE_URL must be an HTTP(S) origin.');
    }
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  final Uri origin;
  final HttpClient _client;
  final Map<String, _SessionCookie> _cookies = {};
  String? _version;
  String? _csrf;
  int _sessionEpoch = 0;
  int get identityEpoch => _sessionEpoch;
  int _readRevision = 0;
  int get readRevision => _readRevision;
  final SessionVault? _vault;
  Future<void> _vaultTail = Future<void>.value();
  bool _persistCookies = true, _rememberLogin = false;
  bool persistenceAvailable = true;
  String? rememberedEmail;
  bool get remembersLogin => _rememberLogin;
  String get _vaultKey => 'bagoo-buyer-session-v1:${origin.origin}';

  Future<void> _vaultOperation(Future<void> Function(SessionVault) action) {
    final vault = _vault;
    if (vault == null) return Future.value();
    _vaultTail = _vaultTail.then((_) async {
      try {
        await action(vault);
        persistenceAvailable = true;
      } catch (_) {
        persistenceAvailable = false;
      }
    });
    return _vaultTail;
  }

  Future<void> restoreSavedSession() async {
    final vault = _vault;
    if (vault == null) return;
    final epoch = _sessionEpoch;
    try {
      final raw = await vault.read(_vaultKey);
      if (raw == null || epoch != _sessionEpoch) return;
      if (raw.length > 65536) throw const FormatException();
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['origin'] != origin.origin ||
          data['remember'] is! bool ||
          data['cookies'] is! List ||
          (data['cookies'] as List).length > 64) {
        throw const FormatException();
      }
      final restored = <String, _SessionCookie>{};
      final now = DateTime.now();
      for (final row in data['cookies']) {
        if (row is! Map ||
            row['header'] is! String ||
            row['expires'] != null && row['expires'] is! String) {
          throw const FormatException();
        }
        final cookie = Cookie.fromSetCookieValue(row['header']);
        final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '');
        if (domain != null &&
            domain.isNotEmpty &&
            origin.host != domain &&
            !origin.host.endsWith('.$domain')) {
          throw const FormatException();
        }
        final expiry = row['expires'] == null
            ? null
            : DateTime.parse(row['expires']);
        if (expiry != null && !expiry.isAfter(now)) continue;
        restored['${cookie.name}|${cookie.path ?? '/'}'] = _SessionCookie(
          cookie,
          expiry,
        );
      }
      if (epoch != _sessionEpoch) return;
      _cookies.addAll(restored);
      _rememberLogin = data['remember'] as bool;
      rememberedEmail =
          _rememberLogin &&
              data['email'] is String &&
              (data['email'] as String).length <= 254
          ? data['email']
          : null;
    } catch (_) {
      if (epoch == _sessionEpoch) {
        await _vaultOperation((vault) => vault.delete(_vaultKey));
      }
    }
  }

  Future<void> _saveSession() {
    if (!_persistCookies || _vault == null) return Future.value();
    final epoch = _sessionEpoch;
    final now = DateTime.now();
    final payload = jsonEncode({
      'origin': origin.origin,
      'remember': _rememberLogin,
      'email': rememberedEmail,
      'cookies': [
        for (final row in _cookies.values)
          if (row.expires == null || row.expires!.isAfter(now))
            {
              'header': row.cookie.toString(),
              'expires': row.expires?.toIso8601String(),
            },
      ],
    });
    return _vaultOperation((vault) async {
      if (epoch == _sessionEpoch && _persistCookies) {
        await vault.write(_vaultKey, payload);
      }
    });
  }

  Future<void> prepareAuthentication() async {
    _sessionEpoch++;
    _persistCookies = false;
    _rememberLogin = false;
    rememberedEmail = null;
    await _vaultOperation((vault) => vault.delete(_vaultKey));
  }

  Future<void> rememberAuthentication(bool remember, String email) async {
    _rememberLogin = remember;
    _persistCookies = remember;
    rememberedEmail = remember ? email.trim().toLowerCase() : null;
    if (remember) await _saveSession();
  }

  Future<void> clearSavedSession() async {
    clear();
    await _vaultTail;
  }

  Uri resolve(String path) {
    final target = origin.resolve(path);
    if (target.origin != origin.origin || target.userInfo.isNotEmpty) {
      throw const BackendException(
        'The server returned an unsupported redirect.',
      );
    }
    return target;
  }

  /// Private media uses the same session, and must stay on the buyer origin.
  Map<String, String> imageHeaders(String path) {
    final target = resolve(path);
    final now = DateTime.now();
    final cookies = _cookies.values.where((stored) {
      final cookie = stored.cookie;
      final prefix = cookie.path ?? '/';
      return (stored.expires == null || stored.expires!.isAfter(now)) &&
          (!cookie.secure || target.scheme == 'https') &&
          (target.path == prefix ||
              target.path.startsWith(
                prefix.endsWith('/') ? prefix : '$prefix/',
              ));
    });
    return {
      if (cookies.isNotEmpty)
        HttpHeaders.cookieHeader: cookies
            .map((c) => '${c.cookie.name}=${c.cookie.value}')
            .join('; '),
    };
  }

  Future<WebPage> page(String path, {bool bootstrap = false}) async {
    final target = resolve(path);
    final response = await _request(
      'GET',
      target,
      inertia: !bootstrap && _version != null,
    );
    if (response.status == 409 && !bootstrap) {
      // Refresh the asset version after a server deployment, without replaying
      // any mutation. A normal HTML visit contains the new version and CSRF.
      return page(path, bootstrap: true);
    }
    return _readPage(response);
  }

  Future<Map<String, dynamic>> jsonGet(String path) async {
    final response = await _request('GET', resolve(path), acceptJson: true);
    return _json(response.body);
  }

  /// Optional capability discovery must not accept a redirected JSON reply.
  Future<Map<String, dynamic>> jsonGetDirect(String path) async {
    final response = await _request(
      'GET',
      resolve(path),
      acceptJson: true,
      allowRedirects: false,
    );
    return _json(response.body);
  }

  Future<Map<String, dynamic>> jsonPost(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
  }) async {
    final response = await _post(
      path,
      values,
      method: method,
      referer: referer,
    );
    final data = _json(response.body);
    if (data['success'] == false) {
      throw BackendException(
        data['message']?.toString() ?? 'Please try again.',
      );
    }
    return data;
  }

  /// Sends a JSON mutation whose successful response has no body (for example,
  /// an optional analytics event returning HTTP 204).
  Future<void> jsonPostNoContent(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
  }) async {
    await _post(path, values, method: method, referer: referer);
  }

  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    final response = await _post(
      path,
      values,
      method: method,
      referer: referer,
      files: files,
    );
    return _readPage(response);
  }

  Future<Map<String, dynamic>> uploadJson(
    String path,
    Map<String, dynamic> values,
    List<UploadPart> files, {
    String? referer,
  }) async {
    final response = await _post(path, values, files: files, referer: referer);
    final data = _json(response.body);
    if (data['success'] == false) {
      throw BackendException(
        data['message']?.toString() ?? 'The upload was not confirmed.',
      );
    }
    return data;
  }

  Future<RemoteDocument> documentBytes(String path) async {
    final response = await _request('GET', resolve(path), binary: true);
    if (!response.mime.startsWith('image/') &&
        response.mime != 'application/pdf') {
      throw const BackendException(
        'This document is unavailable. Sign in again if your session expired.',
      );
    }
    if (response.bytes == null || response.bytes!.isEmpty) {
      throw const BackendException('The document is empty.');
    }
    return RemoteDocument(response.bytes!, response.mime);
  }

  Future<_Reply> _post(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    _readRevision++;
    try {
      final sessionEpoch = _sessionEpoch;
      if (_csrf == null &&
          !_cookies.values.any((c) => c.cookie.name == 'XSRF-TOKEN')) {
        await page('/login', bootstrap: true);
      }
      if (sessionEpoch != _sessionEpoch) {
        throw const BackendException(
          'Your session changed. Start this action again after signing in.',
          status: 401,
        );
      }
      return await _request(
        method,
        resolve(path),
        values: values,
        referer: referer,
        files: files,
      );
    } finally {
      _readRevision++;
    }
  }

  Future<_Reply> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? values,
    bool inertia = false,
    bool acceptJson = false,
    bool binary = false,
    bool allowRedirects = true,
    List<UploadPart>? files,
    String? referer,
    int redirects = 0,
  }) async {
    if (redirects > 5) {
      throw const BackendException(
        'The server redirected too many times. Try again.',
      );
    }
    try {
      final sessionEpoch = _sessionEpoch;
      final request = await _client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      if (sessionEpoch != _sessionEpoch) {
        request.abort();
        throw const BackendException(
          'Your session changed. Start this action again after signing in.',
          status: 401,
        );
      }
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        values != null || acceptJson
            ? 'application/json'
            : 'text/html, application/xhtml+xml',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      if (referer != null) {
        request.headers.set(
          HttpHeaders.refererHeader,
          resolve(referer).toString(),
        );
      }
      final now = DateTime.now();
      _cookies.removeWhere(
        (_, c) => c.expires != null && !c.expires!.isAfter(now),
      );
      for (final stored in _cookies.values) {
        final cookie = stored.cookie;
        final path = cookie.path ?? '/';
        final pathMatches =
            uri.path == path ||
            (uri.path.startsWith(path) &&
                (path.endsWith('/') ||
                    uri.path.substring(path.length).startsWith('/')));
        if (pathMatches && (!cookie.secure || uri.scheme == 'https')) {
          request.cookies.add(Cookie(cookie.name, cookie.value));
        }
      }
      if (inertia) {
        request.headers.set('X-Inertia', 'true');
        request.headers.set('X-Inertia-Version', _version!);
      }
      if (values != null) {
        final cookie = _cookies['XSRF-TOKEN|/']?.cookie.value;
        if (cookie != null) {
          request.headers.set('X-XSRF-TOKEN', Uri.decodeComponent(cookie));
        } else if (_csrf != null) {
          request.headers.set('X-CSRF-TOKEN', _csrf!);
        }
        if (files != null && files.isNotEmpty) {
          final payload = MultipartPayload(values, files);
          request.headers.contentType = ContentType(
            'multipart',
            'form-data',
            parameters: {'boundary': payload.boundary},
          );
          request.contentLength = payload.bytes.length;
          request.add(payload.bytes);
        } else {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(values));
        }
      }
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (sessionEpoch != _sessionEpoch) {
        await response.drain<void>().timeout(const Duration(seconds: 25));
        throw const BackendException(
          'Your session changed. Sign in again before continuing.',
          status: 401,
        );
      }
      final location =
          response.headers.value('x-inertia-location') ??
          response.headers.value(HttpHeaders.locationHeader);
      if (!allowRedirects &&
          (response.statusCode >= 300 && response.statusCode < 400 ||
              response.statusCode == 409 && location != null)) {
        await response.drain<void>().timeout(const Duration(seconds: 25));
        throw BackendException(
          'BagooPH returned an unsupported redirect.',
          status: response.statusCode,
        );
      }
      for (final cookie in response.cookies) {
        final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '');
        if (domain != null &&
            domain.isNotEmpty &&
            uri.host != domain &&
            !uri.host.endsWith('.$domain')) {
          continue;
        }
        _cookies['${cookie.name}|${cookie.path ?? '/'}'] = _SessionCookie(
          cookie,
          cookie.maxAge != null
              ? now.add(Duration(seconds: cookie.maxAge!))
              : cookie.expires,
        );
      }
      await _saveSession();
      final chunks = BytesBuilder(copy: false);
      await for (final bytes in response.timeout(const Duration(seconds: 25))) {
        chunks.add(bytes);
        if (binary && chunks.length > 20 * 1024 * 1024) {
          throw const BackendException(
            'This document is too large to preview.',
          );
        }
      }
      final responseBytes = chunks.takeBytes();
      if (sessionEpoch != _sessionEpoch) {
        throw const BackendException(
          'Your session changed. Sign in again before continuing.',
          status: 401,
        );
      }
      final body = binary && response.statusCode < 400
          ? ''
          : utf8.decode(responseBytes, allowMalformed: true);
      if (([301, 302, 303, 307, 308, 409].contains(response.statusCode)) &&
          location != null &&
          !(response.statusCode == 409 && inertia && method == 'GET')) {
        final target = resolve(uri.resolve(location).toString());
        // Never replay a credential-bearing POST on a redirect.
        return await _request(
          'GET',
          target,
          redirects: redirects + 1,
          binary: binary,
          acceptJson: acceptJson,
        );
      }
      final reply = _Reply(
        response.statusCode,
        body,
        bytes: binary ? responseBytes : null,
        mime: response.headers.contentType?.mimeType ?? '',
      );
      if (response.statusCode >= 400 &&
          !(response.statusCode == 409 && inertia && method == 'GET')) {
        final data = _json(body, optional: true);
        final fields = <String, String>{};
        final errors = data['errors'];
        if (errors is Map) {
          for (final entry in errors.entries) {
            fields[entry.key.toString()] = entry.value is List
                ? (entry.value as List).first.toString()
                : entry.value.toString();
          }
        }
        if (response.statusCode == 419) {
          clear();
        }
        throw BackendException(
          switch (response.statusCode) {
            419 => 'Your session expired. Please try again.',
            429 => 'Too many attempts. Please wait before trying again.',
            500 ||
            502 ||
            503 ||
            504 => 'BagooPH is temporarily unavailable. Please try again.',
            _ =>
              data['message']?.toString() ??
                  'We could not complete this request.',
          },
          fields: fields,
          status: response.statusCode,
          data: data,
        );
      }
      return reply;
    } on SocketException {
      throw const BackendException(
        'Cannot reach BagooPH. Check your connection and try again.',
        connectionFailure: true,
      );
    } on TimeoutException {
      throw const BackendException(
        'The connection timed out. Please try again.',
        connectionFailure: true,
      );
    } on HandshakeException {
      throw const BackendException(
        'A secure connection could not be established.',
        connectionFailure: true,
      );
    } on HttpException {
      throw const BackendException(
        'The connection was interrupted. Please try again.',
        connectionFailure: true,
      );
    }
  }

  WebPage _readPage(_Reply response) {
    Map<String, dynamic> data;
    if (response.body.trimLeft().startsWith('{')) {
      data = _json(response.body);
    } else {
      final document = html.parse(response.body);
      final token = document
          .querySelector('meta[name="csrf-token"]')
          ?.attributes['content'];
      if (token != null) {
        _csrf = token;
      }
      final serialized = document
          .querySelector('[data-page]')
          ?.attributes['data-page'];
      if (serialized == null) {
        throw const BackendException(
          'BagooPH returned an unsupported page. Please try again.',
        );
      }
      data = _json(serialized);
    }
    if (data['component'] is! String || data['props'] is! Map) {
      throw const BackendException(
        'BagooPH returned incomplete page data. Please try again.',
      );
    }
    _version = data['version']?.toString();
    return WebPage(
      data['component'] as String,
      Map<String, dynamic>.from(data['props'] as Map),
      url: data['url']?.toString(),
    );
  }

  Map<String, dynamic> _json(String body, {bool optional = false}) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } on FormatException {
      /* Report a readable protocol error below. */
    }
    if (optional) {
      return {};
    }
    throw const BackendException(
      'BagooPH returned an unexpected response. Please try again.',
    );
  }

  void clear({bool eraseSaved = true}) {
    _sessionEpoch++;
    _cookies.clear();
    _csrf = null;
    _version = null;
    _rememberLogin = false;
    rememberedEmail = null;
    _persistCookies = true;
    if (eraseSaved) {
      unawaited(_vaultOperation((vault) => vault.delete(_vaultKey)));
    }
  }

  void close() {
    clear(eraseSaved: false);
    _client.close(force: true);
  }
}

class WebPage {
  const WebPage(this.component, this.props, {this.url, this.cachedAt});
  final String? url;
  final DateTime? cachedAt;
  bool get isCached => cachedAt != null;
  final String component;
  final Map<String, dynamic> props;
  Map<String, dynamic>? get user {
    final auth = props['auth'];
    final user = auth is Map ? auth['user'] : null;
    return user is Map ? Map<String, dynamic>.from(user) : null;
  }

  Map<String, String> get errors => mapOf(props['errors']).map(
    (key, value) => MapEntry(
      key,
      value is List ? value.first.toString() : value.toString(),
    ),
  );
}

Map<String, dynamic> mapOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> mapsOf(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

class BackendException implements Exception {
  const BackendException(
    this.message, {
    this.fields = const {},
    this.status,
    this.data = const {},
    this.connectionFailure = false,
  });
  final String message;
  final Map<String, String> fields;
  final int? status;
  final Map<String, dynamic> data;
  final bool connectionFailure;
  @override
  String toString() => message;
}

class _SessionCookie {
  const _SessionCookie(this.cookie, this.expires);
  final Cookie cookie;
  final DateTime? expires;
}

class _Reply {
  const _Reply(this.status, this.body, {this.bytes, this.mime = ''});
  final int status;
  final String body;
  final Uint8List? bytes;
  final String mime;
}
