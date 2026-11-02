import '../../core/buyer_repository.dart';
import '../../core/pagination_metadata.dart';
import '../../core/resource_ids.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../products/product_model.dart';

class BuyerEngagementRepository {
  BuyerEngagementRepository(this.buyer);

  static const _noticePreviewLimit = 6;
  static const _noticePageSize = 20;
  static const _collectionPageSize = 24;

  final BuyerRepository buyer;

  int? _nonnegativeCount(Object? value) =>
      value is int && value >= 0 ? value : null;

  Map<String, dynamic>? confirmedNotificationReadSnapshot(Object? value) {
    if (value == null ||
        value is! Map ||
        value.keys.any((key) => key is! String)) {
      return null;
    }
    final snapshot = Map<String, dynamic>.from(value);
    final id = snapshot['id'];
    final count = snapshot['count'];
    final expiresAt = strictDateTime(
      snapshot['expires_at'],
      requireTimezone: true,
    );
    if (id is! String ||
        !_isUuid(id) ||
        count is! int ||
        count < 1 ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    return snapshot;
  }

  List<Map<String, dynamic>>? _completeNoticeRows(
    Object? raw, {
    required int maxRows,
  }) {
    if (raw is! List || raw.length > maxRows) return null;
    final rows = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final row in raw) {
      if (row is! Map || row.keys.any((key) => key is! String)) return null;
      final notice = Map<String, dynamic>.from(row);
      final id = notice['id'];
      final type = notice['type'];
      final data = notice['data'];
      final createdAt = notice['created_at'];
      final readAt = notice['read_at'];
      final href = notice['href'];
      if (id is! String ||
          !_isUuid(id) ||
          !ids.add(id.toLowerCase()) ||
          type is! String ||
          type.trim().isEmpty ||
          !notice.containsKey('read_at') ||
          !notice.containsKey('href') ||
          data is! Map ||
          data.keys.any((key) => key is! String) ||
          createdAt is! String ||
          strictDateTime(createdAt) == null ||
          readAt != null &&
              (readAt is! String || strictDateTime(readAt) == null) ||
          href != null && href is! String) {
        return null;
      }
      for (final field in [
        'title',
        'body',
        'order_number',
        'hub_name',
        'hub_address',
        'operating_hours',
      ]) {
        if (data[field] != null && data[field] is! String) return null;
      }
      final expiresAt = data['expires_at'];
      if (expiresAt != null &&
          (expiresAt is! String || strictDateTime(expiresAt) == null)) {
        return null;
      }
      rows.add(notice);
    }
    return rows;
  }

  bool _validPagePagination(
    Map<String, dynamic> page, {
    required int requestedPage,
    required int rowCount,
    required int pageSize,
  }) =>
      parseContractPaginationMetadata(
        page,
        rowCount: rowCount,
        requestedPage: requestedPage,
        pageSize: pageSize,
      ) !=
      null;

  Future<WebPage> promotion(String slug, {String? publication}) async {
    final query = publication == null || publication.isEmpty
        ? ''
        : '?publication=${Uri.encodeQueryComponent(publication)}';
    final page = await buyer.document(
      '/promotions/${Uri.encodeComponent(slug)}$query',
    );
    buyer.requireNoErrors(page);
    if (page.component != 'Buyer/Promotion' ||
        page.props['promotion'] is! Map) {
      throw const BackendException(
        'This promotion is no longer available. Browse current products instead.',
      );
    }
    if (completeRelatedProducts(page.props['products']) == null) {
      throw const BackendException(
        'This promotion is no longer available. Browse current products instead.',
      );
    }
    return page;
  }

  Future<WebPage> savedProducts({int page = 1}) => _collection(
    '/buyer/saved-products?page=$page',
    'Buyer/SavedProducts',
    requestedPage: page,
  );

  Future<WebPage> followedShops({int page = 1}) => _collection(
    '/buyer/followed-shops?page=$page',
    'Buyer/FollowedShops',
    requestedPage: page,
  );

  Future<WebPage> _collection(
    String path,
    String component, {
    required int requestedPage,
  }) async {
    if (!isValidBuyerPageRequest(requestedPage)) {
      throw const BackendException('Choose a valid saved-list page.');
    }
    final result = await buyer.document(path);
    buyer.requireNoErrors(result);
    final entries = mapOf(result.props['entries']);
    final idKey = component == 'Buyer/SavedProducts' ? 'product_id' : 'shop_id';
    if (result.user?['role'] != 'buyer') {
      throw const BackendException(
        'Sign in to your buyer account to view this saved list.',
        status: 401,
      );
    }
    if (result.component != component) {
      throw const BackendException(
        'This saved list is unavailable for your buyer account.',
      );
    }
    final rawRows = entries['data'];
    if (rawRows is! List || rawRows.length > _collectionPageSize) {
      throw const BackendException(
        'This saved list is unavailable for your buyer account.',
      );
    }
    final rows = requireRowsWithIds(
      rawRows,
      idKey: idKey,
      error: 'This saved list is unavailable for your buyer account.',
    );
    if (!_validPagePagination(
      entries,
      requestedPage: requestedPage,
      rowCount: rows.length,
      pageSize: _collectionPageSize,
    )) {
      throw const BackendException(
        'This saved list is unavailable for your buyer account.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> notificationPreview() async {
    final data = await buyer.session.jsonGet('/notifications/preview');
    final summary = mapOf(data['summary']);
    final notices = _completeNoticeRows(
      data['notices'],
      maxRows: _noticePreviewLimit,
    );
    if (notices == null ||
        summary['available'] != true ||
        _nonnegativeCount(summary['unread']) == null) {
      throw const BackendException(
        'Notifications are temporarily unavailable. Try again shortly.',
      );
    }
    return data;
  }

  Future<WebPage> notifications({String filter = 'all', int page = 1}) async {
    if (!['all', 'unread'].contains(filter) || !isValidBuyerPageRequest(page)) {
      throw const BackendException('Choose a valid notification page.');
    }
    final result = await buyer.document(
      '/notifications?filter=$filter&page=$page',
    );
    buyer.requireNoErrors(result);
    final notices = mapOf(result.props['notices']);
    final noticeRows = _completeNoticeRows(
      notices['data'],
      maxRows: _noticePageSize,
    );
    if (result.component != 'Notifications/Index' ||
        result.user?['role'] != 'buyer' ||
        result.props['portal'] != 'buyer' ||
        result.props['filter'] != filter ||
        result.props['available'] != true ||
        noticeRows == null ||
        !_validPagePagination(
          notices,
          requestedPage: page,
          rowCount: noticeRows.length,
          pageSize: _noticePageSize,
        )) {
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
    if (strictDateTime(result['read_at'], requireTimezone: true) == null) {
      throw const BackendException(
        'The read status was not confirmed. Refresh and try again.',
      );
    }
  }

  Future<int> markDisplayedNotifications(List<String> ids) async {
    if (ids.isEmpty ||
        ids.length > 6 ||
        ids.toSet().length != ids.length ||
        !ids.every(_isUuid)) {
      throw const BackendException(
        'Refresh the displayed notification preview.',
      );
    }
    final result = await buyer.session.jsonPost(
      '/notifications/read-displayed',
      {'ids': ids},
      method: 'PATCH',
    );
    final summary = mapOf(result['summary']);
    final unread = _nonnegativeCount(summary['unread']);
    if (summary['available'] != true || unread == null) {
      throw const BackendException(
        'The read status was not confirmed. Refresh the preview.',
      );
    }
    return unread;
  }

  Future<WebPage> openNotification(String id, int ownerId) async {
    if (!_isUuid(id)) {
      throw const BackendException('This notification is unavailable.');
    }
    final page = await buyer.session.submit('/notifications/$id/read', {
      'open': true,
    }, method: 'PATCH');
    buyer.requireNoErrors(page);
    if (page.user?['role'] != 'buyer' || page.user?['id'] != ownerId) {
      throw const BackendException(
        'Your account changed. Sign in again to view notifications.',
        status: 401,
      );
    }
    return page;
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
    final updated = _nonnegativeCount(result['updated']);
    final unread = _nonnegativeCount(summary['unread']);
    if (updated == null || summary['available'] != true || unread == null) {
      throw const BackendException(
        'BagooPH did not confirm the notification update. Refresh and try again.',
      );
    }
    return unread;
  }

  Future<void> reportAdvertisementClick(Map<String, dynamic> measurement) =>
      reportAdvertisement(measurement, 'click');

  Future<void> reportAdvertisement(
    Map<String, dynamic> measurement,
    String type,
  ) async {
    if (!['impression', 'click'].contains(type)) return;
    final endpoint = measurement['endpoint'];
    final token = measurement['token'];
    if (endpoint is! String || token is! String || token.isEmpty) return;
    await buyer.session.jsonPostNoContent(endpoint, {
      'token': token,
      'type': type,
    });
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
