import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/buyer_repository.dart';
import '../../core/pagination_metadata.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../products/product_model.dart';

List<Map<String, dynamic>> _completeMapRows(Object? value) {
  if (value is! List) return const [];
  final rows = mapsOf(value);
  return rows.length == value.length ? rows : const [];
}

class HomeController extends ChangeNotifier {
  HomeController(this.repository, {WebPage? initial})
    : data = initial,
      _knownUser = initial?.user,
      _knownEpoch = repository.session.identityEpoch {
    if (initial != null) {
      _accept(initial, requestedPage: 1);
      _acceptedRequest = ('', '', 'relevance', currentPage);
    }
  }
  final BuyerRepository repository;
  Map<String, dynamic>? _knownUser;
  int _knownEpoch;
  WebPage? data;
  List<Map<String, dynamic>> products = [];
  bool loading = false;
  bool loadingMore = false;
  String? error;
  String? moreError;
  String search = '';
  String category = '';
  String sort = 'relevance';
  int currentPage = 1;
  int lastPage = 1;
  int total = 0;
  int? from, to;
  int _generation = 0;
  bool _disposed = false;
  (String, String, String, int)? _acceptedRequest;
  List<Map<String, dynamic>> get categories {
    final rows = _completeMapRows(data?.props['categories']);
    final ids = <int>{};
    final slugs = <String>{};
    if (rows.any((row) {
      final id = positiveResourceId(row['id']);
      final name = row['name'];
      final slug = row['slug'];
      return id == null ||
          name is! String ||
          name.trim().isEmpty ||
          slug is! String ||
          slug.trim().isEmpty ||
          !ids.add(id) ||
          !slugs.add(slug);
    })) {
      return const [];
    }
    return rows;
  }

  List<Map<String, dynamic>> get banners {
    final rows = _completeMapRows(data?.props['banners']);
    final ids = <int>{};
    if (rows.any((row) {
      final id = positiveResourceId(row['id']);
      final image = row['image'];
      final href = row['href'];
      final measurement = row['measurement'];
      if (id == null ||
          !ids.add(id) ||
          image is! String ||
          image.trim().isEmpty ||
          href is! String ||
          href.trim().isEmpty) {
        return true;
      }
      if (measurement == null) return false;
      if (measurement is! Map) return true;
      return positiveResourceId(measurement['revision_id']) == null ||
          measurement['token'] is! String ||
          (measurement['token'] as String).isEmpty ||
          measurement['endpoint'] is! String ||
          (measurement['endpoint'] as String).isEmpty;
    })) {
      return const [];
    }
    return rows;
  }

  List<Map<String, dynamic>> get relatedProducts =>
      completeRelatedProducts(data?.props['relatedProducts']) ?? const [];

  Map<String, dynamic>? get user =>
      _knownEpoch == repository.session.identityEpoch
      ? data?.user ?? (data?.isCached == true ? _knownUser : null)
      : null;
  bool get hasMore => data?.isCached != true && currentPage < lastPage;
  bool get isMarketplace => data?.component == 'Buyer/Home';
  bool get hasFilters =>
      search.isNotEmpty || category.isNotEmpty || sort != 'relevance';

  Future<void> load({bool more = false, int? pageNumber}) async {
    if (more && (loading || loadingMore || !hasMore)) {
      return;
    }
    final generation = ++_generation;
    final epoch = repository.session.identityEpoch;
    final cacheGeneration = repository.catalogueCache.generation;
    final request = (
      search,
      category,
      sort,
      more ? currentPage + 1 : pageNumber ?? 1,
    );
    if (!isValidBuyerPageRequest(request.$4)) {
      loading = false;
      loadingMore = false;
      if (more) {
        moreError = 'Choose a valid product page.';
      } else {
        error = 'Choose a valid product page.';
      }
      notifyListeners();
      return;
    }
    if (request.$1.runes.length > 100) {
      loading = false;
      loadingMore = false;
      error = 'Use no more than 100 characters for your search.';
      moreError = null;
      notifyListeners();
      return;
    }
    if (more) {
      loadingMore = true;
      moreError = null;
    } else {
      loading = true;
      loadingMore = false;
      error = null;
      moreError = null;
    }
    notifyListeners();
    try {
      final fresh = repository.home(
        search: request.$1,
        category: request.$2,
        sort: request.$3,
        page: request.$4,
      );
      if (!more &&
          (data == null || data!.isCached || request != _acceptedRequest)) {
        unawaited(
          repository
              .cachedHome(
                search: request.$1,
                category: request.$2,
                sort: request.$3,
                page: request.$4,
              )
              .then<void>((cached) {
                if (cached != null &&
                    !_disposed &&
                    generation == _generation &&
                    loading &&
                    epoch == repository.session.identityEpoch &&
                    cacheGeneration == repository.catalogueCache.generation) {
                  try {
                    _accept(cached, requestedPage: request.$4);
                    _acceptedRequest = request;
                    notifyListeners();
                  } on BackendException {
                    // Ignore malformed or stale local previews.
                  }
                }
              }, onError: (Object _, StackTrace _) {}),
        );
      }
      final page = await fresh;
      if (_disposed || generation != _generation) {
        return;
      }
      if (epoch != repository.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Refresh to continue.',
          status: 401,
        );
      }
      _accept(page, more: more, requestedPage: request.$4);
      _acceptedRequest = request;
    } on BackendException catch (e) {
      if (_disposed || generation != _generation) {
        return;
      }
      if (more) {
        moreError = e.message;
      } else {
        error = e.message;
      }
      if ([401, 403, 404, 419].contains(e.status)) {
        data = null;
        products = [];
        _knownUser = null;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _accept(WebPage page, {bool more = false, required int requestedPage}) {
    final pageUser = page.user;
    if (pageUser != null &&
        (pageUser['role'] != 'buyer' ||
            positiveResourceId(pageUser['id']) == null)) {
      throw const BackendException(
        'Your buyer account could not be confirmed. Sign in again to continue.',
        status: 401,
      );
    }
    if (!page.isCached) {
      _knownUser = page.user;
      _knownEpoch = repository.session.identityEpoch;
    }
    if (page.component != 'Buyer/Home') {
      data = page;
      products = [];
      return;
    }
    final feed = mapOf(page.props['feedProducts']);
    final rows = completeProductCards(feed['data']);
    if (rows == null) {
      throw const BackendException(
        'Product results could not be confirmed. Refresh and try again.',
      );
    }
    final pagination = parseContractPaginationMetadata(
      feed,
      rowCount: rows.length,
      requestedPage: requestedPage,
      pageSize: 18,
    );
    if (pagination == null) {
      throw const BackendException(
        'Home pagination could not be confirmed. Refresh and try again.',
      );
    }
    data = page;
    if (more) {
      final ids = products.map((p) => p['id']).toSet();
      products.addAll(rows.where((p) => ids.add(p['id'])));
    } else {
      products = rows;
    }
    currentPage = pagination.currentPage;
    lastPage = pagination.lastPage;
    total = pagination.total;
    from = more ? from ?? pagination.from : pagination.from;
    to = pagination.to;
  }

  Future<void> filter({String? query, String? department, String? order}) {
    if (query != null) {
      search = query.trim();
    }
    if (department != null) {
      category = department;
    }
    if (order != null) {
      sort = order;
    }
    return load();
  }

  Future<void> reset() {
    search = '';
    category = '';
    sort = 'relevance';
    return load();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
