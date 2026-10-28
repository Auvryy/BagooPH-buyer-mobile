import 'package:flutter/foundation.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

class HomeController extends ChangeNotifier {
  HomeController(this.repository, {WebPage? initial})
    : data = initial,
      _knownUser = initial?.user,
      _knownEpoch = repository.session.identityEpoch;
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
  List<Map<String, dynamic>> get categories =>
      mapsOf(data?.props['categories']);
  List<Map<String, dynamic>> get banners => mapsOf(data?.props['banners']);
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
      final page = await repository.home(
        search: search,
        category: category,
        sort: sort,
        page: more ? currentPage + 1 : pageNumber ?? 1,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      data = page;
      if (!page.isCached) {
        _knownUser = page.user;
        _knownEpoch = repository.session.identityEpoch;
      }
      if (page.component != 'Buyer/Home') {
        products = [];
        return;
      }
      final feed = mapOf(page.props['feedProducts']);
      final fresh = mapsOf(feed['data']);
      if (more) {
        final ids = products.map((p) => p['id']).toSet();
        products.addAll(fresh.where((p) => !ids.contains(p['id'])));
      } else {
        products = fresh;
      }
      currentPage = (feed['current_page'] as num?)?.toInt() ?? 1;
      lastPage = (feed['last_page'] as num?)?.toInt() ?? 1;
      total = (feed['total'] as num?)?.toInt() ?? products.length;
      from = more
          ? from ?? (feed['from'] as num?)?.toInt()
          : (feed['from'] as num?)?.toInt();
      to = (feed['to'] as num?)?.toInt();
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
