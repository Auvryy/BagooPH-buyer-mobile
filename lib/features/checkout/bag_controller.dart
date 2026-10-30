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
    : _epoch = repository.session.identityEpoch,
      selected = {...initialSelection};
  final BuyerRepository repository;
  final int _epoch;
  final Set<int> selected;
  WebPage? data;
  Map<String, dynamic>? quote;
  List<Map<String, dynamic>> offers = [];
  final itemErrors = <int, String>{};
  bool busy = false, quoting = false, _disposed = false, _initialized = false;
  bool _invalid = false, _ownerBound = false;
  int? _owner;
  String? error, quoteError;
  int _quoteGeneration = 0;
  bool get isCurrent =>
      !_disposed && !_invalid && _epoch == repository.session.identityEpoch;
  List<Map<String, dynamic>> get items => mapsOf(data?.props['items']);
  List<Map<String, dynamic>> get selectable =>
      items.where((row) => row['available_for_purchase'] == true).toList();
  bool get approved =>
      isCurrent &&
      data?.user?['role'] == 'buyer' &&
      data?.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(data?.user?['kyc_status']);
  bool get canChange =>
      isCurrent &&
      data != null &&
      (data?.user == null ||
          data?.user?['role'] == 'buyer' &&
              ['active', 'pending_approval'].contains(data?.user?['status']));
  bool get ready =>
      isCurrent &&
      selected.isNotEmpty &&
      quote != null &&
      !busy &&
      !quoting &&
      quoteError == null;

  void invalidate({String? message, bool notify = true}) {
    if (_disposed) return;
    if (!_invalid) {
      _invalid = true;
      data = null;
      selected.clear();
      itemErrors.clear();
      busy = false;
      _invalidateQuote();
      error = message ?? 'Your Bag session changed or access ended. Reopen your Bag to continue.';
    }
    if (notify) notifyListeners();
  }

  bool ensureCurrent({bool notify = true}) {
    if (isCurrent) return true;
    if (!_invalid) invalidate(notify: notify);
    return false;
  }

  void _invalidateQuote() {
    _quoteGeneration++;
    quote = null;
    quoteError = null;
    quoting = false;
    offers = [];
  }

  bool _accept(WebPage page) {
    if (!ensureCurrent()) return false;
    final user = page.user;
    final owner = user?['id'];
    if (page.component != 'Cart/Index' ||
        user != null &&
            (user['role'] != 'buyer' || owner is! int || owner < 1) ||
        _ownerBound && owner != _owner ||
        page.props['cart'] is Map &&
            mapOf(page.props['cart'])['user_id'] != owner) {
      invalidate();
      return false;
    }
    _owner = owner as int?;
    _ownerBound = true;
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
    return true;
  }

  Future<void> load() async {
    if (!ensureCurrent() || busy) return;
    busy = true;
    error = null;
    itemErrors.clear();
    _invalidateQuote();
    notifyListeners();
    try {
      final page = await repository.bag();
      _accept(page);
    } on BackendException catch (e) {
      if (ensureCurrent()) {
        if ([401, 403, 404, 419].contains(e.status)) {
          invalidate(message: e.message);
        } else {
          error = e.message;
        }
      }
    } finally {
      if (ensureCurrent()) {
        busy = false;
        notifyListeners();
      }
    }
    if (isCurrent && error == null) await refreshQuote();
  }

  void select(Iterable<int> ids, bool value) {
    if (!ensureCurrent() || busy || data == null) return;
    final eligible = selectable.map((row) => row['id']).toSet();
    for (final id in ids.where(eligible.contains)) {
      value ? selected.add(id) : selected.remove(id);
    }
    _invalidateQuote();
    notifyListeners();
    refreshQuote();
  }

  Future<void> refreshQuote() async {
    if (!ensureCurrent() || busy || quoting || data == null) return;
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
      if (!ensureCurrent() || generation != _quoteGeneration) return;
      quote = checkedPurchaseQuote(result['quote'], itemIds: ids);
      offers = mapsOf(result['availableVouchers']);
    } on BackendException catch (e) {
      if (ensureCurrent() && generation == _quoteGeneration) {
        if ([401, 403, 404, 419].contains(e.status)) {
          invalidate(message: e.message);
        } else {
          quoteError = e.message;
          quote = null;
        }
      }
    } finally {
      if (ensureCurrent() && generation == _quoteGeneration) {
        quoting = false;
        notifyListeners();
      }
    }
  }

  Future<bool> change(int id, int? quantity) async {
    if (!ensureCurrent() || busy || !canChange) return false;
    final item = items.where((row) => row['id'] == id).firstOrNull;
    if (id < 1 || item == null) {
      error =
          'This item is no longer in your Bag. Refresh your Bag to review it.';
      notifyListeners();
      return false;
    }
    if (quantity != null &&
        (quantity < 1 || quantity > bagMaximumQuantity(item, items))) {
      itemErrors[id] = 'Choose an available quantity or remove this item.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    itemErrors.remove(id);
    _invalidateQuote();
    notifyListeners();
    var saved = false;
    try {
      final page = await repository.changeBagItem(id, quantity);
      saved = _accept(page);
    } on BackendException catch (e) {
      if (ensureCurrent()) {
        if ([401, 403, 404, 419].contains(e.status)) {
          invalidate(message: e.message);
        } else {
          itemErrors[id] = e.fields.isEmpty
              ? e.message
              : e.fields.values.join('\n');
        }
      }
    } finally {
      if (ensureCurrent()) {
        busy = false;
        notifyListeners();
      }
    }
    if (isCurrent && saved) await refreshQuote();
    return saved && ensureCurrent();
  }

  @override
  void dispose() {
    _disposed = true;
    _quoteGeneration++;
    super.dispose();
  }
}
