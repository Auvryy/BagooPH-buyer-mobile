import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/uploads.dart';

class ProfileRepository {
  ProfileRepository(this.buyer);
  final BuyerRepository buyer;
  Map<String, String> _contextQuery = {};
  WebSession get session => buyer.session;

  String path(String tab, [Map<String, String> query = const {}]) => Uri(
    path: '/buyer/profile',
    queryParameters: {'tab': tab, ...query},
  ).toString();

  Future<WebPage> load({
    String tab = 'account',
    Map<String, String> query = const {},
  }) async {
    _contextQuery = Map.of(query);
    return checked(await session.page(path(tab, query)));
  }

  WebPage checked(WebPage page) {
    buyer.requireNoErrors(page);
    final user = mapOf(page.props['user']);
    if (page.component != 'Buyer/Profile' ||
        user['id'] is! num ||
        (user['id'] as num) <= 0 ||
        page.user?['role'] != 'buyer' ||
        user['id'] != page.user?['id']) {
      throw const BackendException(
        'Sign in to your buyer account to load your profile.',
        status: 401,
      );
    }
    return page;
  }

  Future<WebPage> mutate(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    String tab = 'account',
    List<UploadPart>? files,
    bool requireMessage = true,
  }) async {
    final page = checked(
      await session.submit(
        endpoint,
        values,
        method: method,
        referer: path(tab, _contextQuery),
        files: files,
      ),
    );
    if (requireMessage &&
        (mapOf(page.props['flash'])['success']?.toString().trim().isNotEmpty !=
            true)) {
      throw const BackendException(
        'The saved result was not confirmed. Refresh these details before retrying.',
      );
    }
    return page;
  }

  Future<Map<String, dynamic>> json(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    List<UploadPart>? files,
  }) async {
    final data = files != null && files.isNotEmpty
        ? await session.uploadJson(
            endpoint,
            values,
            files,
            referer: path('account'),
          )
        : await session.jsonPost(
            endpoint,
            values,
            method: method,
            referer: path('account'),
          );
    if (![
      'message',
      'reference',
      'id',
      'saved_id',
      'success',
      'result',
      'code',
    ].any(data.containsKey)) {
      throw const BackendException(
        'The server did not confirm this change. Refresh before retrying.',
      );
    }
    return data;
  }

  Future<WebPage> order(int id) async {
    final page = await session.page('/buyer/orders/$id');
    buyer.requireNoErrors(page);
    if (page.component != 'Buyer/OrderDetail' ||
        mapOf(page.props['order'])['id'] != id ||
        page.user?['role'] != 'buyer') {
      throw const BackendException(
        'This order is unavailable for your buyer account.',
      );
    }
    return page;
  }
}
