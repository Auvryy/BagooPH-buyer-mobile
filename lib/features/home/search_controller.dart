import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/buyer_repository.dart';
import '../../core/pagination_metadata.dart';
import '../../core/web_session.dart';
import '../products/product_model.dart';

const searchSorts = {
  'relevance': 'Recommended',
  'top_sales': 'Top sales',
  'top_rated': 'Top rated',
  'newest': 'Latest',
  'price_asc': 'Price: low to high',
  'price_desc': 'Price: high to low',
};

List<Map<String, dynamic>> completeSearchFilterChoices(
  Object? raw, {
  required String valueKey,
  required String labelKey,
}) {
  if (raw is! List) return const [];
  final rows = <Map<String, dynamic>>[];
  final values = <String>{};
  for (final row in raw) {
    if (row is! Map || row.keys.any((key) => key is! String)) return const [];
    final choice = Map<String, dynamic>.from(row);
    final value = choice[valueKey];
    final label = choice[labelKey];
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        label is! String ||
        label.trim().isEmpty ||
        !values.add(value)) {
      return const [];
    }
    rows.add(choice);
  }
  return rows;
}

List<String> _completeSearchSuggestions(Object? raw) {
  if (raw is! List) return const [];
  final suggestions = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! String ||
        item.trim().isEmpty ||
        item != item.trim() ||
        !seen.add(item)) {
      return const [];
    }
    suggestions.add(item);
  }
  return suggestions;
}

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
  List<Map<String, dynamic>> get categories => completeSearchFilterChoices(
    data?.props['categories'],
    valueKey: 'slug',
    labelKey: 'name',
  );
  List<Map<String, dynamic>> get locations => completeSearchFilterChoices(
    data?.props['locations'],
    valueKey: 'value',
    labelKey: 'label',
  );
  List<Map<String, dynamic>> get related =>
      completeRelatedProducts(data?.props['relatedProducts']) ?? const [];
  List<String> get suggestions =>
      _completeSearchSuggestions(data?.props['suggestions']);
  Map<String, dynamic>? get user => data?.user;
  Future<void> apply(SearchFilters value) {
    filters = value;
    return load();
  }

  Future<void> reset() => apply(SearchFilters(query: filters.query));
  Future<void> load({bool more = false, int? pageNumber}) async {
    if (_disposed || more && (loading || loadingMore || !hasMore)) return;
    final generation = ++_generation;
    if (filters.query.runes.length > 100) {
      loading = false;
      loadingMore = false;
      error = 'Use no more than 100 characters for your search.';
      moreError = null;
      notifyListeners();
      return;
    }
    final epoch = repository.session.identityEpoch;
    final cacheGeneration = repository.catalogueCache.generation;
    final parameters = Map<String, String>.of(filters.parameters);
    final number = more ? currentPage + 1 : pageNumber ?? 1;
    if (!isValidBuyerPageRequest(number)) {
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
              try {
                _accept(cached, requestedPage: number);
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
      if (_disposed || generation != _generation) return;
      if (epoch != repository.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Refresh to continue.',
          status: 401,
        );
      }
      _accept(page, more: more, requestedPage: number);
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

  void _accept(WebPage page, {bool more = false, required int requestedPage}) {
    final feed = mapOf(page.props['products']);
    final rows = completeProductCards(feed['data']);
    if (rows == null) {
      throw const BackendException(
        'Search results could not be confirmed. Refresh and try again.',
      );
    }
    final pagination = parseContractPaginationMetadata(
      feed,
      rowCount: rows.length,
      requestedPage: requestedPage,
      pageSize: 24,
    );
    if (pagination == null) {
      throw const BackendException(
        'Search pagination could not be confirmed. Refresh and try again.',
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

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
