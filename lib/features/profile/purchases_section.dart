import 'package:flutter/material.dart';

import '../../app/theme.dart';
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

Future<void> openWalletPayment(
  BuildContext context,
  ProfileRepository repository,
  int id, {
  BuyerAccountScope? parentAccount,
}) async {
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
  final account =
      parentAccount?.fork() ?? BuyerAccountScope(repository.session);
  account.check();
  final response = await repository.json('/buyer/orders/$orderId/buy-again', {
    'mode': 'purchase',
    'request_token': token,
  });
  account.check();
  final rows = mapsOf(mapOf(response['result'])['items']);
  if (mapOf(response['result'])['order_id'] != orderId ||
      rows.isEmpty ||
      rows.any(
        (row) =>
            row['cart_item_id'] is! int || (row['cart_item_id'] as int) <= 0,
      )) {
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
              .map((row) => (row['cart_item_id'] as num).toInt())
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

  Future<void> _confirmReceipt(Map<String, dynamic> order) async {
    final id = order['id'];
    if (busy ||
        widget.loading ||
        _confirming ||
        id is! int ||
        id < 1 ||
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
    if (current?['can_confirm_receipt'] != true) return;
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
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in buyerOrderFilters.entries)
              Semantics(
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
                      '${status.value} (${counts[status.key] ?? 0})',
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
        Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                mapOf(
                      mapOf(
                        mapsOf(order['items']).firstOrNull?['product'],
                      )['shop'],
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
              for (final item in mapsOf(order['items']))
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
                    onPressed: busy || widget.loading
                        ? null
                        : () => perform(() async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OrderDetailPage(
                                  repository: widget.repository,
                                  orderId: (order['id'] as num).toInt(),
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
                      onPressed: busy || widget.loading
                          ? null
                          : () => perform(() async {
                              await openWalletPayment(
                                context,
                                widget.repository,
                                (mapOf(order['wallet_payment'])['id'] as num)
                                    .toInt(),
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
                  if (order['can_confirm_receipt'] == true)
                    FilledButton(
                      onPressed: busy || widget.loading || _confirming
                          ? null
                          : () => _confirmReceipt(order),
                      child: const Text('Confirm Received'),
                    ),
                  if (order['can_buy_again'] == true &&
                      order['buy_again_token'] is String)
                    TextButton(
                      onPressed: busy || widget.loading
                          ? null
                          : () => perform(() async {
                              await buyAgain(
                                context,
                                widget.repository,
                                (order['id'] as num).toInt(),
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
