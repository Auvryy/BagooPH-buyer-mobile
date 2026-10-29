import 'dart:io';

/// Fail locally if a native fixture accidentally reaches an unimplemented route.
class NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Network requests are disabled in the QA preview.');
}
