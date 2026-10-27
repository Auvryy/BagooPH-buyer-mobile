import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../products/product_model.dart';
import 'purchase_quote.dart';

int bagMaximumQuantity(
  Map<String, dynamic> item,
  List<Map<String, dynamic>> items,
) {
  if (item['available_for_purchase'] != true) return 0;
  final product = mapOf(item['product']);
  final variants = mapOf(product['variants']);
  final others = items.where(
    (row) =>
        row['id'] != item['id'] &&
        (row['product_id'] ?? mapOf(row['product'])['id']) ==
            (item['product_id'] ?? product['id']),
  );
  int units(Iterable<Map<String, dynamic>> rows) =>
      rows.fold(0, (n, row) => n + (amount(row['quantity']) ?? 0).toInt());
  final stock = (amount(product['stock']) ?? 0).toInt();
  var maximum = stock - units(others);
  if (mapOf(product['shop'])['vacation_mode'] == true ||
      mapsOf(variants['colors']).any(
        (color) => color['name'] == item['color'] && color['in_stock'] == false,
      )) {
    return 0;
  }
  if (variants['combinations'] is List) {
    final combination = mapsOf(variants['combinations'])
        .where(
          (row) => row['color'] == item['color'] && row['size'] == item['size'],
        )
        .firstOrNull;
    maximum = math.min(
      maximum,
      (amount(combination?['stock']) ?? 0).toInt() -
          units(
            others.where(
              (row) =>
                  row['color'] == item['color'] && row['size'] == item['size'],
            ),
          ),
    );
  } else if (item['size'] != null) {
    final size = mapsOf(variants['sizes'])
        .where((row) => row['name'] == item['size'])
        .firstOrNull;
    if (size != null) {
      maximum = math.min(
        maximum,
        (amount(size['stock']) ?? 0).toInt() -
            units(others.where((row) => row['size'] == item['size'])),
      );
    }
  }
  return maximum.clamp(0, 99);
}

class BagController extends ChangeNotifier {
  BagController(this.repository, {List<int> initialSelection = const []})
    : selected = {...initialSelection};
  final BuyerRepository repository;
  final Set<int> selected;
  WebPage? data;
  Map<String, dynamic>? quote;
  List<Map<String, dynamic>> offers = [];
  final itemErrors = <int, String>{};
  bool busy = false, quoting = false, _disposed = false, _initialized = false;
  String? error, quoteError;
  int _quoteGeneration = 0;
  List<Map<String, dynamic>> get items => mapsOf(data?.props['items']);
  List<Map<String, dynamic>> get selectable =>
      items.where((row) => row['available_for_purchase'] == true).toList();
  bool get approved =>
      data?.user?['role'] == 'buyer' &&
      data?.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(data?.user?['kyc_status']);
  bool get canChange =>
      data?.user == null ||
      data?.user?['role'] == 'buyer' &&
          ['active', 'pending_approval'].contains(data?.user?['status']);
  bool get ready =>
      selected.isNotEmpty &&
      quote != null &&
      !busy &&
      !quoting &&
      quoteError == null;
  void _invalidateQuote() {
    _quoteGeneration++;
    quote = null;
    quoteError = null;
    quoting = false;
    offers = [];
  }

  void _accept(WebPage page) {
    data = page;
    final eligible = selectable.map((row) => row['id']).toSet();
    if (!_initialized) {
      final fromServer = page.props['selectedBagItemIds'];
      if (selected.isEmpty) {
        if (fromServer is List) {
          selected.addAll(fromServer.whereType<num>().map((id) => id.toInt()));
        } else if (selectable.isNotEmpty) {
          selected.add((selectable.first['id'] as num).toInt());
        }
      }
      _initialized = true;
    }
    selected.removeWhere((id) => !eligible.contains(id));
  }

  Future<void> load() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    itemErrors.clear();
    _invalidateQuote();
    notifyListeners();
    try {
      final page = await repository.bag();
      if (!_disposed) _accept(page);
    } on BackendException catch (e) {
      if (!_disposed) {
        error = e.message;
        if (e.status == 401 || e.status == 419) {
          data = null;
          selected.clear();
          error = e.message;
        }
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
    if (!_disposed && error == null) await refreshQuote();
  }

  void select(Iterable<int> ids, bool value) {
    if (busy || _disposed) return;
    final eligible = selectable.map((row) => row['id']).toSet();
    for (final id in ids.where(eligible.contains)) {
      value ? selected.add(id) : selected.remove(id);
    }
    _invalidateQuote();
    notifyListeners();
    refreshQuote();
  }

  Future<void> refreshQuote() async {
    if (_disposed || busy) return;
    final generation = ++_quoteGeneration;
    quote = null;
    quoteError = null;
    offers = [];
    if (selected.isEmpty) {
      quoting = false;
      notifyListeners();
      return;
    }
    final ids = selected.toList()..sort();
    quoting = true;
    notifyListeners();
    try {
      final result = await repository.bagQuote(ids);
      if (_disposed || generation != _quoteGeneration) return;
      quote = checkedPurchaseQuote(result['quote'], itemIds: ids);
      offers = mapsOf(result['availableVouchers']);
    } on BackendException catch (e) {
      if (!_disposed && generation == _quoteGeneration) {
        quoteError = e.message;
        quote = null;
      }
    } finally {
      if (!_disposed && generation == _quoteGeneration) {
        quoting = false;
        notifyListeners();
      }
    }
  }

  Future<bool> change(int id, int? quantity) async {
    if (busy || _disposed || !canChange) return false;
    busy = true;
    error = null;
    itemErrors.remove(id);
    _invalidateQuote();
    notifyListeners();
    var saved = false;
    try {
      final page = await repository.changeBagItem(id, quantity);
      if (!_disposed) {
        _accept(page);
        saved = true;
      }
    } on BackendException catch (e) {
      if (!_disposed) {
        itemErrors[id] = e.fields.isEmpty
            ? e.message
            : e.fields.values.join('\n');
        if (e.status == 401 || e.status == 419) {
          data = null;
          selected.clear();
          error = e.message;
        }
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
    if (!_disposed && saved) await refreshQuote();
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    _quoteGeneration++;
    super.dispose();
  }
}
