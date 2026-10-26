import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

/// The buyer backend currently exposes Laravel web sessions and Inertia pages.
/// Cookies stay in memory and are never written to disk or logged.
class WebSession {
  WebSession(this.origin, {HttpClient? client})
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

  Uri resolve(String path) {
    final target = origin.resolve(path);
    if (target.origin != origin.origin || target.userInfo.isNotEmpty) {
      throw const BackendException(
        'The server returned an unsupported redirect.',
      );
    }
    return target;
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
    final response = await _request('GET', resolve(path));
    return _json(response.body);
  }

  Future<Map<String, dynamic>> jsonPost(
    String path,
    Map<String, dynamic> values,
  ) async {
    final response = await _post(path, values);
    final data = _json(response.body);
    if (data['success'] == false) {
      throw BackendException(
        data['message']?.toString() ?? 'Please try again.',
      );
    }
    return data;
  }

  Future<WebPage> submit(String path, Map<String, dynamic> values) async {
    final response = await _post(path, values);
    return _readPage(response);
  }

  Future<_Reply> _post(String path, Map<String, dynamic> values) async {
    if (_csrf == null &&
        !_cookies.values.any((c) => c.cookie.name == 'XSRF-TOKEN')) {
      await page('/login', bootstrap: true);
    }
    return _request('POST', resolve(path), values: values);
  }

  Future<_Reply> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? values,
    bool inertia = false,
    int redirects = 0,
  }) async {
    if (redirects > 5) {
      throw const BackendException(
        'The server redirected too many times. Try again.',
      );
    }
    try {
      final request = await _client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        method == 'POST'
            ? 'application/json'
            : 'text/html, application/xhtml+xml',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
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
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(values));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
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
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 25));
      final location =
          response.headers.value('x-inertia-location') ??
          response.headers.value(HttpHeaders.locationHeader);
      if (([301, 302, 303, 307, 308, 409].contains(response.statusCode)) &&
          location != null &&
          !(response.statusCode == 409 && inertia && method == 'GET')) {
        final target = resolve(uri.resolve(location).toString());
        // Never replay a credential-bearing POST on a redirect.
        return await _request('GET', target, redirects: redirects + 1);
      }
      final reply = _Reply(response.statusCode, body);
      if (response.statusCode >= 400 && response.statusCode != 409) {
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
          _csrf = null;
          _cookies.clear();
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
        );
      }
      return reply;
    } on SocketException {
      throw const BackendException(
        'Cannot reach BagooPH. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const BackendException(
        'The connection timed out. Please try again.',
      );
    } on HandshakeException {
      throw const BackendException(
        'A secure connection could not be established.',
      );
    } on HttpException {
      throw const BackendException(
        'The connection was interrupted. Please try again.',
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

  void clear() {
    _cookies.clear();
    _csrf = null;
    _version = null;
  }

  void close() {
    clear();
    _client.close(force: true);
  }
}

class WebPage {
  const WebPage(this.component, this.props);
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
  const BackendException(this.message, {this.fields = const {}, this.status});
  final String message;
  final Map<String, String> fields;
  final int? status;
  @override
  String toString() => message;
}

class _SessionCookie {
  const _SessionCookie(this.cookie, this.expires);
  final Cookie cookie;
  final DateTime? expires;
}

class _Reply {
  const _Reply(this.status, this.body);
  final int status;
  final String body;
}
