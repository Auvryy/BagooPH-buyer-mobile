import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

const searchSorts = {
  'relevance': 'Recommended',
  'top_sales': 'Top sales',
  'top_rated': 'Top rated',
  'newest': 'Latest',
  'price_asc': 'Price: low to high',
  'price_desc': 'Price: high to low',
};

class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.category = '',
    this.location = '',
    this.minimum = '',
    this.maximum = '',
    this.rating = '',
    this.inStock = false,
    this.sort = 'relevance',
  });
  final String query, category, location, minimum, maximum, rating, sort;
  final bool inStock;
  SearchFilters copyWith({
    String? query,
    String? category,
    String? location,
    String? minimum,
    String? maximum,
    String? rating,
    bool? inStock,
    String? sort,
  }) => SearchFilters(
    query: query ?? this.query,
    category: category ?? this.category,
    location: location ?? this.location,
    minimum: minimum ?? this.minimum,
    maximum: maximum ?? this.maximum,
    rating: rating ?? this.rating,
    inStock: inStock ?? this.inStock,
    sort: sort ?? this.sort,
  );
  int get count => [
    category.isNotEmpty,
    location.isNotEmpty,
    minimum.isNotEmpty || maximum.isNotEmpty,
    rating.isNotEmpty,
    inStock,
  ].where((v) => v).length;
  Map<String, String> get parameters => {
    if (query.trim().isNotEmpty) 'search': query.trim(),
    if (category.isNotEmpty) 'category': category,
    if (location.isNotEmpty) 'location': location,
    if (minimum.isNotEmpty) 'min_price': minimum,
    if (maximum.isNotEmpty) 'max_price': maximum,
    if (rating.isNotEmpty) 'rating': rating,
    if (inStock) 'in_stock': '1',
    if (sort != 'relevance') 'sort': sort,
  };
  static String? priceError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(text) ||
        (double.tryParse(text) ?? double.infinity) > 99999999.99) {
      return 'Use an amount from 0 to 99,999,999.99.';
    }
    return null;
  }
}

class CatalogueSearchController extends ChangeNotifier {
  CatalogueSearchController(this.repository);
  final BuyerRepository repository;
  SearchFilters filters = const SearchFilters();
  WebPage? data;
  List<Map<String, dynamic>> products = [];
  bool loading = false, loadingMore = false, _disposed = false;
  String? error, moreError;
  int currentPage = 1, lastPage = 1, total = 0, _generation = 0;
  int? from, to;
  (String, int)? _acceptedRequest;
  bool get hasMore => data?.isCached != true && currentPage < lastPage;
  List<Map<String, dynamic>> get categories =>
      mapsOf(data?.props['categories']);
  List<Map<String, dynamic>> get locations => mapsOf(data?.props['locations']);
  List<Map<String, dynamic>> get related =>
      mapsOf(data?.props['relatedProducts']);
  List<String> get suggestions =>
      (data?.props['suggestions'] as List? ?? []).whereType<String>().toList();
  Map<String, dynamic>? get user => data?.user;
  Future<void> apply(SearchFilters value) {
    filters = value;
    return load();
  }

  Future<void> reset() => apply(SearchFilters(query: filters.query));
  Future<void> load({bool more = false, int? pageNumber}) async {
    if (_disposed || more && (loading || loadingMore || !hasMore)) return;
    final generation = ++_generation;
    final epoch = repository.session.identityEpoch;
    final cacheGeneration = repository.catalogueCache.generation;
    final parameters = Map<String, String>.of(filters.parameters);
    final number = more ? currentPage + 1 : pageNumber ?? 1;
    final request = (Uri(queryParameters: parameters).query, number);
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
      final fresh = repository.search(parameters, page: number);
      if (!more &&
          (data == null || data!.isCached || request != _acceptedRequest)) {
        unawaited(
          repository.cachedSearch(parameters, page: number).then<void>((
            cached,
          ) {
            if (cached != null &&
                !_disposed &&
                generation == _generation &&
                loading &&
                epoch == repository.session.identityEpoch &&
                cacheGeneration == repository.catalogueCache.generation) {
              _accept(cached);
              _acceptedRequest = request;
              notifyListeners();
            }
          }, onError: (Object _, StackTrace _) {}),
        );
      }
      final page = await fresh;
      if (_disposed || generation != _generation) return;
      if (epoch != repository.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Refresh to continue.',
          status: 401,
        );
      }
      _accept(page, more: more);
      _acceptedRequest = request;
    } on BackendException catch (e) {
      if (_disposed || generation != _generation) return;
      if (more) {
        moreError = e.message;
      } else {
        error = e.fields.isEmpty ? e.message : e.fields.values.join('\n');
      }
      if ([401, 403, 404, 410, 419].contains(e.status)) {
        products = [];
        data = null;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _accept(WebPage page, {bool more = false}) {
    final feed = mapOf(page.props['products']);
    final rows = mapsOf(feed['data']);
    data = page;
    if (more) {
      final ids = products.map((p) => p['id']).toSet();
      products.addAll(rows.where((p) => ids.add(p['id'])));
    } else {
      products = rows;
    }
    currentPage = (feed['current_page'] as num?)?.toInt() ?? 1;
    lastPage = (feed['last_page'] as num?)?.toInt() ?? 1;
    total = (feed['total'] as num?)?.toInt() ?? products.length;
    from = more
        ? from ?? (feed['from'] as num?)?.toInt()
        : (feed['from'] as num?)?.toInt();
    to = (feed['to'] as num?)?.toInt();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
