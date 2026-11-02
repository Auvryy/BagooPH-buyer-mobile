import 'dart:convert';

import 'pagination_metadata.dart';
import 'resource_ids.dart';
import 'session_vault.dart';
import 'strict_datetime.dart';
import 'web_session.dart';

const _maxCatalogueProductsPerPage = 24;

/// Only public catalogue projections belong here. Never persist an Inertia
/// response or authenticated media. All cached pages are read-only.
class CatalogueCache {
  CatalogueCache({
    required this.origin,
    this.vault,
    DateTime Function()? clock,
    this.maxEntries = 32,
    this.maxBytes = 768 * 1024,
    this.maxAge = const Duration(days: 7),
  }) : _clock = clock ?? DateTime.now;

  final Uri origin;
  final SessionVault? vault;
  final DateTime Function() _clock;
  final int maxEntries, maxBytes;
  final Duration maxAge;
  final _entries = <String, Map<String, dynamic>>{};
  Future<void> _tail = Future.value();
  bool _loaded = false;
  int _generation = 0;
  int get generation => _generation;
  String get _key => 'bagoo-buyer-catalogue-v1:${origin.origin}';

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await vault?.read(_key);
      if (raw == null || utf8.encode(raw).length > maxBytes) return;
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['origin'] != origin.origin ||
          data['version'] != 1 ||
          data['entries'] is! Map) {
        return;
      }
      for (final row in (data['entries'] as Map).entries.take(maxEntries)) {
        if (row.key is String &&
            (row.key as String).length <= 2048 &&
            row.value is Map) {
          final stored = mapOf(row.value);
          if (stored['component'] is! String || stored['props'] is! Map) {
            continue;
          }
          final props = _publicProps(
            WebPage(stored['component'], mapOf(stored['props'])),
          );
          if (props != null) {
            _entries[row.key] = {
              'at': stored['at'],
              'component': stored['component'],
              'props': props,
            };
          }
        }
      }
      _prune();
      await _persist();
    } catch (_) {
      // Corrupt or unavailable storage cannot prevent ordinary shopping.
      _entries.clear();
    }
  }

  void _prune() {
    final now = _clock();
    _entries.removeWhere((key, row) {
      final date = strictDateTime(row['at'], requireTimezone: true);
      return date == null || date.isAfter(now) || now.difference(date) > maxAge;
    });
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    while (_entries.isNotEmpty && utf8.encode(_encode()).length > maxBytes) {
      _entries.remove(_entries.keys.first);
    }
  }

  String _encode() =>
      jsonEncode({'version': 1, 'origin': origin.origin, 'entries': _entries});

  Future<bool> _persist() async {
    try {
      if (_entries.isEmpty) {
        await vault?.delete(_key);
      } else {
        await vault?.write(_key, _encode());
      }
      return true;
    } catch (_) {
      /* A memory cache remains useful without native storage. */
      return false;
    }
  }

  Future<void> save(String key, WebPage page, {int? generation}) {
    final revision = generation ?? _generation;
    return _serial(() async {
      await _load();
      if (revision != _generation) return;
      final props = _publicProps(page);
      if (props == null || key.length > 2048 || page.isCached) return;
      final entry = {
        'at': _clock().toUtc().toIso8601String(),
        'component': page.component,
        'props': props,
      };
      if (utf8.encode(jsonEncode(entry)).length > 96 * 1024) return;
      _entries.remove(key);
      _entries[key] = entry;
      _prune();
      await _persist();
    });
  }

  Future<WebPage?> read(String key) => _serial(() async {
    await _load();
    final count = _entries.length;
    _prune();
    if (_entries.length != count) await _persist();
    final row = _entries[key];
    final cachedAt = strictDateTime(row?['at'], requireTimezone: true);
    if (row == null ||
        cachedAt == null ||
        row['component'] is! String ||
        row['props'] is! Map) {
      return null;
    }
    // Apply the allowlist again on restore, including storage from older builds.
    final props = _publicProps(WebPage(row['component'], mapOf(row['props'])));
    if (props == null) return null;
    return WebPage(row['component'], props, cachedAt: cachedAt);
  });

  Future<void> remove(String key) {
    _generation++;
    return _serial(() async {
      await _load();
      _entries.remove(key);
      await _persist();
    });
  }

  Future<bool> clear() {
    _generation++;
    return _serial(() async {
      _loaded = true;
      _entries.clear();
      return _persist();
    });
  }
}

Map<String, dynamic> _scalars(dynamic value, List<String> keys) {
  final source = mapOf(value);
  return {
    for (final key in keys)
      if (source[key] is String && (source[key] as String).length <= 12000 ||
          source[key] is num ||
          source[key] is bool)
        key: source[key],
  };
}

Map<String, dynamic> _category(dynamic row, [int depth = 0]) => {
  ..._scalars(row, ['id', 'slug', 'name']),
  if (depth < 3)
    'children': mapsOf(mapOf(row)['children'])
        .take(100)
        .map((child) => _category(child, depth + 1))
        .toList(),
};

List<Map<String, dynamic>>? _categoryRows(dynamic value) {
  if (value is! List) return null;
  final rows = mapsOf(value);
  final ids = <int>{};
  final slugs = <String>{};
  if (rows.length != value.length ||
      rows.any((row) {
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
    return null;
  }
  return rows.take(100).map(_category).toList();
}

Map<String, dynamic> _product(dynamic row) {
  final p = mapOf(row);
  return {
    ..._scalars(p, [
      'id',
      'slug',
      'name',
      'description',
      'price',
      'compare_at_price',
      'featured_image',
      'stock',
      'rating',
      'sales_count',
      'brand',
      'condition',
      'sku',
      'weight_kg',
    ]),
    'category': _category(p['category']),
    'shop': _scalars(p['shop'], [
      'id',
      'slug',
      'name',
      'city',
      'province',
      'status',
      'vacation_mode',
    ]),
    'price_range': _scalars(p['price_range'], [
      'min',
      'max',
      'regular_min',
      'regular_max',
    ]),
    'images': mapsOf(p['images'])
        .take(20)
        .map((i) => _scalars(i, ['image_url']))
        .toList(),
  };
}

List<Map<String, dynamic>>? _products(dynamic value) {
  if (value is! List || value.length > _maxCatalogueProductsPerPage) {
    return null;
  }
  final rows = mapsOf(value);
  if (rows.length != value.length ||
      rows.any(
        (product) =>
            positiveResourceId(product['id']) == null ||
            product['slug'] is! String ||
            product['name'] is! String,
      )) {
    return null;
  }
  return rows.map(_product).toList();
}

Map<String, dynamic>? _paginator(dynamic value, {required int pageSize}) {
  if (value is! Map) return null;
  final page = mapOf(value);
  final rawProducts = page['data'];
  final products = _products(rawProducts);
  if (products == null) return null;
  final currentPage = page['current_page'];
  final pagination = parseContractPaginationMetadata(
    page,
    rowCount: (rawProducts as List).length,
    requestedPage: currentPage is int ? currentPage : 0,
    pageSize: pageSize,
  );
  if (pagination == null) return null;
  return {
    ..._scalars(page, [
      'current_page',
      'last_page',
      'per_page',
      'total',
      'from',
      'to',
    ]),
    'data': products,
  };
}

Map<String, dynamic>? _publicProps(WebPage page) {
  final p = page.props;
  switch (page.component) {
    case 'Buyer/Home':
      if (p['feedProducts'] is! Map) return null;
      final feed = _paginator(p['feedProducts'], pageSize: 18);
      if (feed == null) return null;
      return {
        'feedProducts': feed,
        'categories':
            _categoryRows(p['categories']) ?? <Map<String, dynamic>>[],
      };
    case 'Buyer/Search':
      if (p['products'] is! Map) return null;
      final products = _paginator(p['products'], pageSize: 24);
      if (products == null) return null;
      return {
        'products': products,
        'categories':
            _categoryRows(p['categories']) ?? <Map<String, dynamic>>[],
        'locations': mapsOf(p['locations'])
            .take(100)
            .map(
              (r) => _scalars(r, [
                'id',
                'value',
                'label',
                'slug',
                'name',
                'province',
                'city',
                'code',
                'type',
              ]),
            )
            .toList(),
      };
    case 'Buyer/ProductDetail':
      final product = mapOf(p['product']);
      if (positiveResourceId(product['id']) == null ||
          product['slug'] is! String ||
          product['name'] is! String) {
        return null;
      }
      final variants = mapOf(p['variations']);
      return {
        'product': _product(product),
        'variations': {
          ..._scalars(variants, ['pricing_mode']),
          for (final key in ['colors', 'sizes', 'combinations'])
            if (variants[key] is List)
              key: mapsOf(variants[key])
                  .take(200)
                  .map(
                    (v) => _scalars(v, [
                      'name',
                      'color',
                      'size',
                      'price',
                      'extra_price',
                      'stock',
                      'in_stock',
                      'image_url',
                    ]),
                  )
                  .toList(),
        },
      };
    default:
      return null;
  }
}
