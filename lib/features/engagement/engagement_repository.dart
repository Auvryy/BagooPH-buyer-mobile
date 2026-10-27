import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

class BuyerEngagementRepository {
  BuyerEngagementRepository(this.buyer);

  final BuyerRepository buyer;

  Future<WebPage> promotion(String slug, {String? publication}) async {
    final query = publication == null || publication.isEmpty
        ? ''
        : '?publication=${Uri.encodeQueryComponent(publication)}';
    final page = await buyer.document(
      '/promotions/${Uri.encodeComponent(slug)}$query',
    );
    buyer.requireNoErrors(page);
    if (page.component != 'Buyer/Promotion' ||
        page.props['promotion'] is! Map ||
        page.props['products'] is! List) {
      throw const BackendException(
        'This promotion is no longer available. Browse current products instead.',
      );
    }
    return page;
  }

  Future<WebPage> savedProducts({int page = 1}) =>
      _collection('/buyer/saved-products?page=$page', 'Buyer/SavedProducts');

  Future<WebPage> followedShops({int page = 1}) =>
      _collection('/buyer/followed-shops?page=$page', 'Buyer/FollowedShops');

  Future<WebPage> _collection(String path, String component) async {
    final page = await buyer.document(path);
    buyer.requireNoErrors(page);
    final entries = mapOf(page.props['entries']);
    if (page.component != component ||
        page.user?['role'] != 'buyer' ||
        entries['data'] is! List ||
        entries['current_page'] is! num ||
        entries['last_page'] is! num) {
      throw const BackendException(
        'This saved list is unavailable for your buyer account.',
      );
    }
    return page;
  }

  Future<Map<String, dynamic>> notificationPreview() async {
    final data = await buyer.session.jsonGet('/notifications/preview');
    final summary = mapOf(data['summary']);
    if (data['notices'] is! List ||
        summary['available'] != true ||
        summary['unread'] is! num) {
      throw const BackendException(
        'Notifications are temporarily unavailable. Try again shortly.',
      );
    }
    return data;
  }

  Future<WebPage> notifications({String filter = 'all', int page = 1}) async {
    if (!['all', 'unread'].contains(filter) || page < 1) {
      throw const BackendException('Choose a valid notification page.');
    }
    final result = await buyer.document(
      '/notifications?filter=$filter&page=$page',
    );
    buyer.requireNoErrors(result);
    final notices = mapOf(result.props['notices']);
    if (result.component != 'Notifications/Index' ||
        result.user?['role'] != 'buyer' ||
        result.props['portal'] != 'buyer' ||
        result.props['filter'] != filter ||
        result.props['available'] != true ||
        notices['data'] is! List ||
        notices['current_page'] is! num ||
        notices['last_page'] is! num) {
      throw const BackendException(
        'Notifications are temporarily unavailable. Try again shortly.',
      );
    }
    return result;
  }

  Future<void> markNotificationRead(String id) async {
    if (!_isUuid(id)) {
      throw const BackendException('This notification is unavailable.');
    }
    final result = await buyer.session.jsonPost(
      '/notifications/$id/read',
      {},
      method: 'PATCH',
    );
    if (result['read_at'] is! String) {
      throw const BackendException(
        'The read status was not confirmed. Refresh and try again.',
      );
    }
  }

  Future<int> markNotificationSnapshotRead(String snapshot) async {
    if (!_isUuid(snapshot)) {
      throw const BackendException(
        'This notification list is out of date. Refresh and try again.',
      );
    }
    final result = await buyer.session.jsonPost('/notifications/read-all', {
      'snapshot': snapshot,
    }, method: 'PATCH');
    final summary = mapOf(result['summary']);
    if (result['updated'] is! num ||
        summary['available'] != true ||
        summary['unread'] is! num) {
      throw const BackendException(
        'BagooPH did not confirm the notification update. Refresh and try again.',
      );
    }
    return (summary['unread'] as num).toInt();
  }

  Future<void> reportAdvertisementClick(
    Map<String, dynamic> measurement,
  ) async {
    final endpoint = measurement['endpoint'];
    final token = measurement['token'];
    if (endpoint is! String || token is! String || token.isEmpty) return;
    await buyer.session.jsonPostNoContent(endpoint, {
      'token': token,
      'type': 'click',
    });
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
