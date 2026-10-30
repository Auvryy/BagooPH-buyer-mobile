import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_widgets.dart';
import '../profile/order_detail_page.dart';
import '../profile/profile_repository.dart';

class OrderResultPage extends StatefulWidget {
  const OrderResultPage({
    super.key,
    required this.repository,
    required this.initial,
    this.now = DateTime.now,
    this.account,
  });
  final BuyerRepository repository;
  final WebPage initial;
  final DateTime Function() now;
  final BuyerAccountScope? account;
  @override
  State<OrderResultPage> createState() => _OrderResultPageState();
}

class _OrderResultPageState extends State<OrderResultPage>
    with WidgetsBindingObserver {
  late WebPage _page;
  late final BuyerAccountScope _account;
  bool get _current =>
      _account.isCurrent &&
      identical(_account.session, widget.repository.session);
  void _discardPrivate() {
    _account.invalidate();
    _page = const WebPage('Auth/Login', {});
    _deadline?.cancel();
    _checkedDeadlines.clear();
    _confirmed = false;
    _busy = false;
    _error = 'Your buyer account changed or access ended. Reopen your recorded orders from your account.';
  }

  bool _ensureAccount() {
    if (!mounted) return false;
    try {
      _checkOwner(_page);
      return true;
    } on BackendException {
      setState(_discardPrivate);
      return false;
    }
  }

  bool _lostAccess(BackendException error) {
    if (!_current || [401, 403, 404, 419].contains(error.status)) {
      if (mounted) setState(_discardPrivate);
      return true;
    }
    return false;
  }

  bool _busy = false;
  bool _confirmed = false;
  String? _error;
  Timer? _deadline;
  final _checkedDeadlines = <String>{};
  bool get _canPay {
    final payment = mapOf(_page.props['payment']);
    final expiry = DateTime.tryParse(payment['expires_at']?.toString() ?? '');
    return _current &&
        payment['can_pay'] == true &&
        payment['status'] == 'pending' &&
        expiry != null &&
        expiry.isAfter(widget.now());
  }

  @override
  void initState() {
    super.initState();
    _page = widget.initial;
    _account =
        widget.account?.fork() ?? BuyerAccountScope(widget.repository.session);
    WidgetsBinding.instance.addObserver(this);
    try {
      _checkOwner(_page);
    } on BackendException {
      _discardPrivate();
      return;
    }
    _scheduleDeadline();
  }

  void _scheduleDeadline() {
    _deadline?.cancel();
    final payment = mapOf(_page.props['payment']);
    final expiry = DateTime.tryParse(payment['expires_at']?.toString() ?? '');
    if (expiry == null || payment['status'] != 'pending') return;
    final key = '${payment['id']}:${payment['expires_at']}';
    if (_checkedDeadlines.contains(key)) return;
    final delay = expiry.difference(widget.now());
    _deadline = Timer(
      delay.isNegative
          ? Duration.zero
          : delay + const Duration(milliseconds: 50),
      () {
        if (!mounted) return;
        _checkedDeadlines.add(key);
        setState(() => _confirmed = false);
        if (!_busy) _refresh();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _ensureAccount() &&
        !_busy &&
        mapOf(_page.props['payment']).isNotEmpty) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _account.invalidate();
    _deadline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _checkOwner(WebPage page) {
    if (!identical(_account.session, widget.repository.session)) {
      _account.invalidate();
    }
    _account.check(page: page);
  }

  @override
  void didUpdateWidget(OrderResultPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_current ||
        !identical(oldWidget.initial, widget.initial) ||
        !identical(oldWidget.account, widget.account)) {
      _discardPrivate();
    }
  }

  Future<void> _openOrder(dynamic value) async {
    if (!_ensureAccount() || _busy || value is! num || value <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          repository: ProfileRepository(widget.repository),
          orderId: value.toInt(),
        ),
      ),
    );
  }

  Future<void> _refresh({int? number}) async {
    if (!_ensureAccount() || _busy) return;
    final payment = mapOf(_page.props['payment']);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.document(
        payment.isEmpty
            ? '/buyer/orders?page=${number ?? 1}'
            : '/wallet/payments/${payment['id']}',
      );
      _checkOwner(page);
      widget.repository.requireNoErrors(page);
      if (payment.isEmpty
          ? page.props['orders'] is! Map
          : page.props['payment'] is! Map) {
        throw const BackendException(
          'These order details are unavailable. Sign in again if your session expired.',
        );
      }
      if (mounted) {
        setState(() {
          _page = page;
          _confirmed = false;
        });
        _scheduleDeadline();
      }
    } on BackendException catch (e) {
      if (_lostAccess(e)) return;
      if (mounted) {
        setState(() {
          _error = e.message;
          if ([401, 403, 419].contains(e.status)) {
            _page = const WebPage('Auth/Login', {});
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payment(String action) async {
    if (!_ensureAccount() || _busy) {
      return;
    }
    final payment = mapOf(_page.props['payment']);
    if (action == 'pay' && !_canPay) {
      setState(
        () => _error =
            'This payment needs a fresh server review before it can be paid.',
      );
      return;
    }
    if (action == 'pay' && !_confirmed) {
      setState(() => _error = 'Confirm the exact wallet amount before paying.');
      return;
    }
    if (action == 'cancel') {
      final consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel this wallet payment?'),
          content: const Text(
            'The order will not be paid with wallet credits.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep payment'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel payment'),
            ),
          ],
        ),
      );
      if (!mounted || !_ensureAccount() || consent != true) {
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.session.jsonPost(
        '/wallet/payments/${payment['id']}/$action',
        {
          'request_token': payment['request_token'],
          'payment_confirmed': _confirmed,
        },
      );
      if (!mounted || !_ensureAccount()) return;
      final updated = await widget.repository.document(
        '/wallet/payments/${payment['id']}',
      );
      _checkOwner(updated);
      widget.repository.requireNoErrors(updated);
      if (updated.props['payment'] is! Map) {
        throw const BackendException(
          'Refresh this payment to check its recorded status.',
        );
      }
      if (mounted) {
        setState(() {
          _page = updated;
          _confirmed = false;
        });
        _scheduleDeadline();
      }
    } on BackendException catch (e) {
      if (_lostAccess(e)) return;
      if (mounted) {
        setState(
          () => _error = e.fields.isEmpty
              ? e.message
              : e.fields.values.join('\n'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openPayment(int id) async {
    if (!_ensureAccount() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.document('/wallet/payments/$id');
      _checkOwner(page);
      widget.repository.requireNoErrors(page);
      if (page.props['payment'] is! Map) {
        throw const BackendException('This wallet payment is unavailable.');
      }
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderResultPage(
              repository: widget.repository,
              initial: page,
              account: _account,
            ),
          ),
        );
      }
    } on BackendException catch (e) {
      if (_lostAccess(e)) return;
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recorded orders unavailable')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Notice(
                'Your buyer account changed or access ended. Reopen your recorded orders from your account.',
                error: true,
              ),
            ),
          ),
        ),
      );
    }
    final payment = mapOf(_page.props['payment']);
    final orders = mapsOf(mapOf(_page.props['orders'])['data']);
    final message = mapOf(_page.props['flash'])['success'];
    final expiry = DateTime.tryParse(payment['expires_at']?.toString() ?? '');
    final canPay = _canPay;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(payment.isEmpty ? 'Your orders' : 'Bagoo Wallet payment'),
          actions: [
            IconButton(
              tooltip: 'Refresh recorded status',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (message is String)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Notice(message),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Notice(_error!, error: true),
                    ),
                  if (payment.isNotEmpty)
                    ProductPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ProductHeading('Order ${payment['order_number']}'),
                          Text('Reference: ${payment['reference']}'),
                          if (payment['order_id'] is num)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _openOrder(payment['order_id']),
                              child: const Text('View order and delivery'),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            pesos((amount(payment['amount_cents']) ?? 0) / 100),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Status: ${payment['status']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Available virtual credits: ${payment['balance_cents'] == null ? 'Unavailable' : pesos((amount(payment['balance_cents']) ?? 0) / 100)}',
                          ),
                          Text(
                            'Payment deadline: ${readableDateTime(payment['expires_at'])}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (payment['status'] == 'pending' &&
                              expiry != null &&
                              !expiry.isAfter(widget.now()))
                            const Notice(
                              'The payment deadline has passed. Only the server can confirm its final status.',
                            ),
                          for (final line in mapsOf(payment['items']))
                            Text(
                              '${line['name']} × ${line['quantity']} · ${pesos(line['unit_price'])} each',
                              style: const TextStyle(height: 1.7),
                            ),
                          if (payment['paid_at'] != null)
                            Text(
                              'Paid: ${readableDateTime(payment['paid_at'])}',
                              style: const TextStyle(height: 1.7),
                            ),
                          if (payment['payment_reference'] != null)
                            SelectableText(
                              'Wallet receipt: ${payment['payment_reference']}',
                            ),
                          if ((amount(payment['refunded_cents']) ?? 0) > 0)
                            Text(
                              'Refunded: ${pesos((amount(payment['refunded_cents']) ?? 0) / 100)}\nRefund reference: ${payment['refund_reference'] ?? 'Not recorded'}',
                              style: const TextStyle(height: 1.7),
                            ),
                          if (payment['last_attempt'] is Map)
                            Text(
                              'Last attempt: ${mapOf(payment['last_attempt'])['outcome']} · ${readableDateTime(mapOf(payment['last_attempt'])['created_at'])}\n${mapOf(payment['last_attempt'])['message'] ?? ''}',
                              style: const TextStyle(height: 1.7),
                            ),
                          const SizedBox(height: 16),
                          if (payment['status'] == 'paid')
                            const Notice(
                              'Wallet payment recorded. Reopening this page does not deduct more credits.',
                            )
                          else if (canPay) ...[
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _confirmed,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                        setState(() => _confirmed = v ?? false),
                              title: Text(
                                'I confirm paying ${pesos((amount(payment['amount_cents']) ?? 0) / 100)} in virtual wallet credits for this order.',
                              ),
                            ),
                            FilledButton(
                              onPressed: _busy ? null : () => _payment('pay'),
                              child: const Text('Confirm payment'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _payment('cancel'),
                              child: const Text('Cancel payment'),
                            ),
                          ] else
                            const Text(
                              'This payment cannot accept further credits. Check its recorded status.',
                            ),
                        ],
                      ),
                    ),
                  if (orders.isNotEmpty) ...[
                    const ProductHeading('Your recent orders'),
                    for (final order in orders)
                      ProductPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order ${order['order_number']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text('Status: ${order['status']}'),
                            if (order['id'] is num)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _openOrder(order['id']),
                                child: const Text('View order details'),
                              ),
                            Text('Total: ${pesos(order['total_amount'])}'),
                            Text(
                              'Payment: ${order['payment_method'] ?? 'Not provided'} · ${order['payment_status'] ?? 'Not provided'}',
                            ),
                            if (order['wallet_payment'] != null)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _openPayment(
                                        (mapOf(order['wallet_payment'])['id']
                                                as num)
                                            .toInt(),
                                      ),
                                child: const Text('Review wallet payment'),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (orders.isEmpty && payment.isEmpty)
                    const Text('No orders recorded.'),
                  if (payment.isEmpty &&
                      (amount(mapOf(_page.props['orders'])['last_page']) ?? 1) >
                          1)
                    Wrap(
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed:
                              _busy ||
                                  (amount(
                                            mapOf(
                                              _page.props['orders'],
                                            )['current_page'],
                                          ) ??
                                          1) <=
                                      1
                              ? null
                              : () => _refresh(
                                  number:
                                      (amount(
                                                mapOf(
                                                  _page.props['orders'],
                                                )['current_page'],
                                              ) ??
                                              1)
                                          .toInt() -
                                      1,
                                ),
                          child: const Text('Previous orders'),
                        ),
                        TextButton(
                          onPressed:
                              _busy ||
                                  (amount(
                                            mapOf(
                                              _page.props['orders'],
                                            )['current_page'],
                                          ) ??
                                          1) >=
                                      (amount(
                                            mapOf(
                                              _page.props['orders'],
                                            )['last_page'],
                                          ) ??
                                          1)
                              ? null
                              : () => _refresh(
                                  number:
                                      (amount(
                                                mapOf(
                                                  _page.props['orders'],
                                                )['current_page'],
                                              ) ??
                                              1)
                                          .toInt() +
                                      1,
                                ),
                          child: const Text('Next orders'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst),
                    child: const Text('Return to marketplace'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
