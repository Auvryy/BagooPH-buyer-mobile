import 'package:bagoo_buyer_mobile/core/web_session.dart';

typedef JsonMutation = ({
  String path,
  String method,
  Map<String, dynamic> values,
});

class ControlledWebSession extends WebSession {
  ControlledWebSession() : super(Uri.parse('http://localhost'));

  final posts = <JsonMutation>[];
  final pageRequests = <String>[];
  final getRequests = <String>[];
  Future<Map<String, dynamic>> Function(JsonMutation request)? onPost;
  Future<Map<String, dynamic>> Function(String path)? onGet;
  Future<WebPage> Function(String path)? onPage;

  @override
  Future<Map<String, dynamic>> jsonPost(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
  }) async {
    final request = (
      path: path,
      method: method,
      values: Map<String, dynamic>.of(values),
    );
    posts.add(request);
    if (onPost == null) throw StateError('Unexpected mutation: $method $path');
    return onPost!(request);
  }

  @override
  Future<Map<String, dynamic>> jsonGet(String path) async {
    getRequests.add(path);
    if (onGet == null) throw StateError('Unexpected JSON read: $path');
    return onGet!(path);
  }

  @override
  Future<WebPage> page(String path, {bool bootstrap = false}) async {
    pageRequests.add(path);
    if (onPage == null) throw StateError('Unexpected page read: $path');
    return onPage!(path);
  }
}
