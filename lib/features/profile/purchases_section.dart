import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/count_metadata.dart';
import '../../core/web_session.dart';
import '../../core/buyer_repository.dart';
import '../../core/buyer_account_scope.dart';
import '../products/product_page.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../checkout/bag_page.dart';
import '../checkout/order_result_page.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';
import 'order_detail_page.dart';

const buyerOrderFilters = {
  'all': 'All',
  'to_pay': 'To pay',
  'to_ship': 'To ship',
  'in_transit': 'In transit',
  'delivered': 'Delivered',
  'completed': 'Completed',
  'delivery_failed': 'Delivery issue',
  'returned': 'Returned',
  'cancelled': 'Cancelled',
  'return_refund': 'Return/Refund',
};

int? _positiveId(dynamic value) => value is int && value > 0 ? value : null;

List<Map<String, dynamic>>? completePurchaseItems(Object? value) {
  if (value is! List || value.isEmpty) return null;
  final rows = mapsOf(value);
  final ids = <int>{};
  if (rows.length != value.length) return null;
  for (final row in rows) {
    final id = _positiveId(row['id']);
    final quantity = row['quantity'];
    final unitPrice = amount(row['unit_price']);
    final subtotal = amount(row['subtotal']);
    final rawProduct = row['product'];
    if (id == null ||
        !ids.add(id) ||
        quantity is! int ||
        quantity < 1 ||
        unitPrice == null ||
        unitPrice < 0 ||
        subtotal == null ||
        subtotal < 0 ||
        (unitPrice * quantity * 100).round() != (subtotal * 100).round() ||
        rawProduct != null && rawProduct is! Map ||
        row['color'] != null && row['color'] is! String ||
        row['size'] != null && row['size'] is! String ||
        row['sku_snapshot'] != null && row['sku_snapshot'] is! String) {
      return null;
    }
    final product = mapOf(rawProduct);
    final name = product['name'];
    if (name != null && (name is! String || name.trim().isEmpty)) return null;
    if ((name is! String || name.trim().isEmpty) &&
        (row['sku_snapshot'] is! String ||
            (row['sku_snapshot'] as String).trim().isEmpty)) {
      return null;
    }
  }
  return rows;
}

Future<void> openWalletPayment(
  BuildContext context,
  ProfileRepository repository,
  int id, {
  BuyerAccountScope? parentAccount,
}) async {
  if (id < 1) {
    throw const BackendException('This wallet payment is unavailable.');
  }
  final account =
      parentAccount?.fork() ?? BuyerAccountScope(repository.session);
  account.check();
  final page = await repository.buyer.document('/wallet/payments/$id');
  account.check(page: page);
  repository.buyer.requireNoErrors(page);
  if (page.component != 'Buyer/WalletPayment' ||
      page.props['payment'] is! Map ||
      mapOf(page.props['payment'])['id'] != id) {
    throw const BackendException('This wallet payment is unavailable.');
  }
  if (context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderResultPage(
          repository: repository.buyer,
          initial: page,
          account: account,
        ),
      ),
    );
  }
}

Future<void> buyAgain(
  BuildContext context,
  ProfileRepository repository,
  int orderId,
  String token, {
  BuyerAccountScope? parentAccount,
}) async {
  if (orderId < 1) {
    throw const BackendException('This order is unavailable for your account.');
  }
  final account =
      parentAccount?.fork() ?? BuyerAccountScope(repository.session);
  account.check();
  final response = await repository.json('/buyer/orders/$orderId/buy-again', {
    'mode': 'purchase',
    'request_token': token,
  });
  account.check();
  final result = mapOf(response['result']);
  final rawItems = result['items'];
  final rows = mapsOf(rawItems);
  final cartItemIds = <int>{};
  if (result['order_id'] != orderId ||
      rawItems is! List ||
      rows.length != rawItems.length ||
      rows.isEmpty ||
      rows.any((row) {
        final id = _positiveId(row['cart_item_id']);
        return id == null || !cartItemIds.add(id);
      })) {
    throw const BackendException(
      'The Buy again selection was not confirmed. Check your Bag before retrying.',
    );
  }
  if (context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BagPage(
          repository: repository.buyer,
          account: account,
          initialSelection: rows
              .map((row) => row['cart_item_id'] as int)
              .toList(),
        ),
      ),
    );
  }
}

class PurchasesSection extends StatefulWidget {
  const PurchasesSection({
    super.key,
    required this.repository,
    required this.page,
    required this.onQuery,
    required this.reload,
    this.loading = false,
    this.account,
  });
  final ProfileRepository repository;
  final WebPage page;
  final void Function(String status, int number) onQuery;
  final Future<void> Function() reload;
  final bool loading;
  final BuyerAccountScope? account;
  @override
  State<PurchasesSection> createState() => _PurchasesSectionState();
}

class _PurchasesSectionState extends BuyerProfileFormState<PurchasesSection> {
  bool _confirming = false;
  final _filterScroll = ScrollController();
  final _filterKeys = {
    for (final status in buyerOrderFilters.keys) status: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant PurchasesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.props['currentOrderStatus'] !=
        widget.page.props['currentOrderStatus']) {
      _revealSelected();
    }
  }

  void _revealSelected() {
    final status = widget.page.props['currentOrderStatus']?.toString() ?? 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_filterScroll.hasClients ||
          (widget.page.props['currentOrderStatus']?.toString() ?? 'all') !=
              status) {
        return;
      }
      final target = _filterKeys[status]?.currentContext?.findRenderObject();
      if (target != null) {
        _filterScroll.position.ensureVisible(
          target,
          alignment: .5,
          duration: Duration.zero,
        );
      }
    });
  }

  @override
  void dispose() {
    _filterScroll.dispose();
    super.dispose();
  }

  Future<void> _confirmReceipt(Map<String, dynamic> order) async {
    final id = order['id'];
    if (busy ||
        widget.loading ||
        _confirming ||
        id is! int ||
        id < 1 ||
        completePurchaseItems(order['items']) == null ||
        !ensureBuyerAccess()) {
      return;
    }
    setState(() => _confirming = true);
    var confirmed = false;
    try {
      confirmed = await confirmAction(
        context,
        'Confirm receipt?',
        'Confirm that you received this order and checked its items. This records your receipt and completes the purchase.',
        'Confirm Received',
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (!confirmed || !mounted || !ensureBuyerAccess()) return;
    final current = mapsOf(mapOf(widget.page.props['orders'])['data'])
        .where((row) => row['id'] == id)
        .firstOrNull;
    if (current?['can_confirm_receipt'] != true ||
        completePurchaseItems(current?['items']) == null) {
      return;
    }
    await perform(() async {
      final result = await widget.repository.mutate(
        '/buyer/orders/$id/confirm',
        {},
        tab: 'orders',
      );
      checkBuyerAccount(result: result);
      await widget.reload();
      return 'Receipt confirmed.';
    }, validate: false);
  }

  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  @override
  BuyerAccountScope? get parentAccountScope => widget.account;
  @override
  void clearBuyerDraft() {}

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (widget.loading || _confirming) return Future.value(false);
    return super.perform(action, validate: validate);
  }

  @override
  Widget build(BuildContext context) {
    final paginator = mapOf(widget.page.props['orders']);
    final counts = mapOf(widget.page.props['orderCounts']);
    final current =
        widget.page.props['currentOrderStatus']?.toString() ?? 'all';
    return content([
      const ProfileHeading(
        'My Purchases & Order Tracking',
        'Review your purchases and follow the recorded parcel journey.',
        Icons.inventory_2_outlined,
      ),
      SingleChildScrollView(
        controller: _filterScroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in buyerOrderFilters.entries)
              Semantics(
                key: _filterKeys[status.key],
                button: true,
                selected: current == status.key,
                child: InkWell(
                  onTap: busy || widget.loading
                      ? null
                      : () {
                          if (!_confirming && ensureBuyerAccess()) {
                            widget.onQuery(status.key, 1);
                          }
                        },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: current == status.key
                              ? BagooTheme.strong
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      '${status.value} (${nonNegativeCount(counts[status.key])?.toString() ?? (counts[status.key] == null ? '0' : '—')})',
                      style: TextStyle(
                        color: current == status.key
                            ? BagooTheme.strong
                            : BagooTheme.muted,
                        fontSize: 13,
                        fontWeight: current == status.key
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (widget.loading) const LinearProgressIndicator(),
      if (mapsOf(paginator['data']).isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: BagooTheme.muted,
              ),
              SizedBox(height: 16),
              Text(
                'No orders found in this status',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Your purchases will appear here.',
                style: TextStyle(height: 1.7),
              ),
            ],
          ),
        ),
      for (final order in mapsOf(paginator['data']))
        Builder(
          builder: (context) {
            final orderItems = completePurchaseItems(order['items']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    mapOf(
                          mapOf(orderItems?.firstOrNull?['product'])['shop'],
                        )['name']?.toString() ??
                        'Purchase',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Order #${order['order_number']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.6,
                    ),
                  ),
                  Text(
                    mapOf(order['tracking'])['status_label']?.toString() ??
                        order['status']?.toString().replaceAll('_', ' ') ??
                        'Status not loaded',
                    style: const TextStyle(
                      color: BagooTheme.strong,
                      fontWeight: FontWeight.w700,
                      height: 1.7,
                    ),
                  ),
                  const Divider(height: 24),
                  if (orderItems == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Order item details are incomplete. Refresh this order before confirming receipt.',
                        style: TextStyle(color: BagooTheme.muted, height: 1.6),
                      ),
                    ),
                  for (final item
                      in orderItems ?? const <Map<String, dynamic>>[])
                    OrderItemSummary(
                      item: item,
                      session: widget.repository.session,
                      repository: widget.repository.buyer,
                    ),
                  if (order['delivery'] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Tracking: ${mapOf(order['delivery'])['tracking_number'] ?? 'Not recorded'}\n${mapOf(order['tracking'])['stage_label'] ?? ''}\nHolder: ${mapOf(order['tracking'])['custodian'] ?? 'Not recorded'}',
                        style: const TextStyle(fontSize: 12, height: 1.7),
                      ),
                    ),
                  Text(
                    'Order total: ${pesos(order['total_amount'])}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.7,
                    ),
                  ),
                  Text(
                    'Payment: ${order['payment_method'] ?? 'Not recorded'} · ${order['payment_status'] ?? 'Not recorded'}',
                    style: const TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            busy ||
                                widget.loading ||
                                _positiveId(order['id']) == null
                            ? null
                            : () => perform(() async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => OrderDetailPage(
                                      repository: widget.repository,
                                      orderId: _positiveId(order['id'])!,
                                    ),
                                  ),
                                );
                                await widget.reload();
                                return null;
                              }, validate: false),
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Track Parcel'),
                      ),
                      if (order['wallet_payment'] is Map)
                        TextButton(
                          onPressed:
                              busy ||
                                  widget.loading ||
                                  _positiveId(
                                        mapOf(order['wallet_payment'])['id'],
                                      ) ==
                                      null
                              ? null
                              : () => perform(() async {
                                  await openWalletPayment(
                                    context,
                                    widget.repository,
                                    _positiveId(
                                      mapOf(order['wallet_payment'])['id'],
                                    )!,
                                    parentAccount: accountScope,
                                  );
                                  await widget.reload();
                                  return null;
                                }, validate: false),
                          child: Text(
                            order['payment_status'] == 'pending'
                                ? 'Pay with wallet'
                                : 'Wallet payment',
                          ),
                        ),
                      if (order['can_confirm_receipt'] == true &&
                          orderItems != null)
                        FilledButton(
                          onPressed: busy || widget.loading || _confirming
                              ? null
                              : () => _confirmReceipt(order),
                          child: const Text('Confirm Received'),
                        ),
                      if (order['can_buy_again'] == true &&
                          order['buy_again_token'] is String &&
                          _positiveId(order['id']) != null)
                        TextButton(
                          onPressed: busy || widget.loading
                              ? null
                              : () => perform(() async {
                                  await buyAgain(
                                    context,
                                    widget.repository,
                                    _positiveId(order['id'])!,
                                    order['buy_again_token'],
                                    parentAccount: accountScope,
                                  );
                                  return null;
                                }, validate: false),
                          child: const Text('Buy again'),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                ],
              ),
            );
          },
        ),
      ProfilePagination(paginator, (number) {
        if (!_confirming && ensureBuyerAccess()) {
          widget.onQuery(current, number);
        }
      }, disabled: busy || widget.loading),
    ]);
  }
}

class OrderItemSummary extends StatelessWidget {
  const OrderItemSummary({
    super.key,
    required this.item,
    required this.session,
    this.repository,
  });
  final BuyerRepository? repository;
  final Map<String, dynamic> item;
  final WebSession session;
  @override
  Widget build(BuildContext context) {
    final product = mapOf(item['product']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RemoteImage(
                thumbnail: true,
                uri: imageUri(session, product['featured_image']),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']?.toString() ??
                      item['sku_snapshot']?.toString() ??
                      'Purchased item',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                if (repository != null && product['slug'] is String)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductPage(
                          repository: repository!,
                          slug: product['slug'],
                        ),
                      ),
                    ),
                    child: const Text('View product'),
                  ),
                if (item['color'] != null || item['size'] != null)
                  Text(
                    [
                      item['color'],
                      item['size'],
                    ].whereType<String>().join(' · '),
                    style: const TextStyle(fontSize: 12, height: 1.7),
                  ),
                Text(
                  'Qty: ${item['quantity']} · Unit: ${pesos(item['unit_price'])}',
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
                Text(
                  'Subtotal: ${pesos(item['subtotal'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
