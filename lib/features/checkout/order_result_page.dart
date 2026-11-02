import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/pagination_metadata.dart';
import '../../core/retry_cooldown.dart';
import '../../core/resource_ids.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_widgets.dart';
import '../profile/order_detail_page.dart';
import '../profile/profile_repository.dart';

int? _paymentCents(Object? value) => value is int && value >= 0 ? value : null;

List<Map<String, dynamic>>? _paymentItems(Object? value) {
  if (value is! List) return null;
  final rows = <Map<String, dynamic>>[];
  for (final raw in value) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) return null;
    final row = Map<String, dynamic>.from(raw);
    final name = row['name'];
    final quantity = row['quantity'];
    final unitPrice = amount(row['unit_price']);
    if (name is! String ||
        name.trim().isEmpty ||
        quantity is! int ||
        quantity < 1 ||
        unitPrice == null ||
        unitPrice < 0) {
      return null;
    }
    rows.add(row);
  }
  return rows;
}

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
  bool _cancelDialogOpen = false;
  String? _error;
  Timer? _deadline;
  late final RetryCooldown _paymentCooldown;
  final _checkedDeadlines = <String>{};
  bool get _canCancel {
    final payment = mapOf(_page.props['payment']);
    final expiry = strictDateTime(payment['expires_at']);
    return positiveResourceId(payment['id']) != null &&
        _current &&
        payment['can_pay'] == true &&
        payment['status'] == 'pending' &&
        expiry != null &&
        expiry.isAfter(widget.now());
  }

  bool get _canPay {
    final payment = mapOf(_page.props['payment']);
    return _canCancel &&
        _paymentCents(payment['amount_cents']) != null &&
        (payment['items'] == null || _paymentItems(payment['items']) != null);
  }

  @override
  void initState() {
    super.initState();
    _page = widget.initial;
    _account =
        widget.account?.fork() ?? BuyerAccountScope(widget.repository.session);
    _paymentCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    }, now: widget.now);
    WidgetsBinding.instance.addObserver(this);
    try {
      _checkOwner(_page);
    } on BackendException {
      _discardPrivate();
      return;
    }
    if (_page.props['orders'] is Map && _ordersPagination(_page) == null) {
      _error = 'Recorded order pagination could not be confirmed. Refresh and try again.';
    }
    _scheduleDeadline();
  }

  void _scheduleDeadline() {
    _deadline?.cancel();
    final payment = mapOf(_page.props['payment']);
    final expiry = strictDateTime(payment['expires_at']);
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
    _paymentCooldown.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _checkOwner(WebPage page) {
    if (!identical(_account.session, widget.repository.session)) {
      _account.invalidate();
    }
    _account.check(page: page);
  }

  PaginationMetadata? _ordersPagination(
    WebPage page, {
    bool requirePageNumbers = false,
  }) {
    final raw = page.props['orders'];
    final orders = mapOf(raw);
    final data = orders['data'];
    if (raw is! Map || data is! List) return null;
    final rows = mapsOf(data);
    if (rows.length != data.length) return null;
    return parsePaginationMetadata(
      orders,
      rowCount: rows.length,
      requirePageNumbers: requirePageNumbers,
    );
  }

  void _requirePaymentId(WebPage page, int expectedId) {
    final payment = mapOf(page.props['payment']);
    if (page.props['payment'] is! Map ||
        positiveResourceId(payment['id']) != expectedId) {
      throw const BackendException(
        'This wallet payment could not be confirmed. Refresh your orders.',
      );
    }
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
    final id = positiveResourceId(value);
    if (!_ensureAccount() || _busy || id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          repository: ProfileRepository(widget.repository),
          orderId: id,
        ),
      ),
    );
  }

  Future<void> _refresh({int? number}) async {
    if (!_ensureAccount() || _busy) return;
    final payment = mapOf(_page.props['payment']);
    final paymentId = positiveResourceId(payment['id']);
    if (payment.isNotEmpty && paymentId == null) {
      setState(
        () =>
            _error = 'This wallet payment is unavailable. Refresh your orders.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.document(
        payment.isEmpty
            ? '/buyer/orders?page=${number ?? 1}'
            : '/wallet/payments/$paymentId',
      );
      _checkOwner(page);
      widget.repository.requireNoErrors(page);
      if (payment.isEmpty &&
          _ordersPagination(page, requirePageNumbers: true) == null) {
        throw const BackendException(
          'Recorded order pagination could not be confirmed. Refresh and try again.',
        );
      }
      if (payment.isNotEmpty) _requirePaymentId(page, paymentId!);
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
    if (!_ensureAccount() ||
        _busy ||
        _cancelDialogOpen ||
        _paymentCooldown.active) {
      return;
    }
    final payment = mapOf(_page.props['payment']);
    final paymentId = positiveResourceId(payment['id']);
    if (paymentId == null) {
      setState(
        () =>
            _error = 'This wallet payment is unavailable. Refresh your orders.',
      );
      return;
    }
    if (action == 'pay' && !_canPay) {
      setState(
        () => _error =
            'This payment needs a fresh server review before it can be paid.',
      );
      return;
    }
    if (action == 'cancel' && !_canCancel) {
      setState(
        () => _error = 'This payment needs a fresh server review before it can be cancelled.',
      );
      return;
    }
    if (action == 'pay' && !_confirmed) {
      setState(() => _error = 'Confirm the exact wallet amount before paying.');
      return;
    }
    if (action == 'cancel') {
      bool decided = false;
      bool? consent;
      void finishConfirmation(BuildContext dialogContext, bool value) {
        if (decided ||
            !dialogContext.mounted ||
            ModalRoute.of(dialogContext)?.isCurrent != true) {
          return;
        }
        decided = true;
        Navigator.pop(dialogContext, value);
      }

      _cancelDialogOpen = true;
      try {
        consent = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel this wallet payment?'),
            content: const Text(
              'The order will not be paid with wallet credits.',
            ),
            actions: [
              TextButton(
                onPressed: () => finishConfirmation(context, false),
                child: const Text('Keep payment'),
              ),
              FilledButton(
                onPressed: () => finishConfirmation(context, true),
                child: const Text('Cancel payment'),
              ),
            ],
          ),
        );
      } finally {
        _cancelDialogOpen = false;
      }
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
        '/wallet/payments/$paymentId/$action',
        {
          'request_token': payment['request_token'],
          'payment_confirmed': _confirmed,
        },
      );
      if (!mounted || !_ensureAccount()) return;
      final updated = await widget.repository.document(
        '/wallet/payments/$paymentId',
      );
      _checkOwner(updated);
      widget.repository.requireNoErrors(updated);
      _requirePaymentId(updated, paymentId);
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
        if (e.status == 429) {
          _paymentCooldown.start(e.data, retryAt: e.retryAt, notify: false);
        }
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
      _requirePaymentId(page, id);
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
    final ordersMap = mapOf(_page.props['orders']);
    final ordersPagination = _ordersPagination(_page);
    final ordersAreValid = ordersMap.isEmpty || ordersPagination != null;
    final orders = ordersAreValid
        ? mapsOf(ordersMap['data'])
        : const <Map<String, dynamic>>[];
    final message = mapOf(_page.props['flash'])['success'];
    final expiry = strictDateTime(payment['expires_at']);
    final amountCents = _paymentCents(payment['amount_cents']);
    final balanceCents = _paymentCents(payment['balance_cents']);
    final paymentItems = payment['items'] == null
        ? const <Map<String, dynamic>>[]
        : _paymentItems(payment['items']);
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
                          if (positiveResourceId(payment['order_id']) != null)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _openOrder(payment['order_id']),
                              child: const Text('View order and delivery'),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            amountCents == null
                                ? 'Payment amount unavailable'
                                : pesos(amountCents / 100),
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
                            'Available virtual credits: ${balanceCents == null ? 'Unavailable' : pesos(balanceCents / 100)}',
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
                          if (payment['items'] != null && paymentItems == null)
                            const Notice(
                              'Order item details could not be confirmed. Refresh recorded status before continuing.',
                              error: true,
                            )
                          else
                            for (final line
                                in paymentItems ??
                                    const <Map<String, dynamic>>[])
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
                                'I confirm paying ${pesos(amountCents! / 100)} in virtual wallet credits for this order.',
                              ),
                            ),
                            FilledButton(
                              onPressed: _busy || _paymentCooldown.active
                                  ? null
                                  : () => _payment('pay'),
                              child: Text(
                                _paymentCooldown.active
                                    ? 'Try again in ${_paymentCooldown.remainingSeconds}s'
                                    : 'Confirm payment',
                              ),
                            ),
                            TextButton(
                              onPressed: _busy || _paymentCooldown.active
                                  ? null
                                  : () => _payment('cancel'),
                              child: Text(
                                _paymentCooldown.active
                                    ? 'Cancel payment in ${_paymentCooldown.remainingSeconds}s'
                                    : 'Cancel payment',
                              ),
                            ),
                          ] else if (amountCents == null) ...[
                            const Notice(
                              'Payment amount could not be confirmed. Refresh recorded status before continuing.',
                              error: true,
                            ),
                            if (_canCancel)
                              TextButton(
                                onPressed: _busy || _paymentCooldown.active
                                    ? null
                                    : () => _payment('cancel'),
                                child: Text(
                                  _paymentCooldown.active
                                      ? 'Cancel payment in ${_paymentCooldown.remainingSeconds}s'
                                      : 'Cancel payment',
                                ),
                              ),
                          ] else if (payment['items'] != null &&
                              paymentItems == null) ...[
                            if (_canCancel)
                              TextButton(
                                onPressed: _busy || _paymentCooldown.active
                                    ? null
                                    : () => _payment('cancel'),
                                child: Text(
                                  _paymentCooldown.active
                                      ? 'Cancel payment in ${_paymentCooldown.remainingSeconds}s'
                                      : 'Cancel payment',
                                ),
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
                            if (positiveResourceId(order['id']) != null)
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
                            if (positiveResourceId(
                                  mapOf(order['wallet_payment'])['id'],
                                ) !=
                                null)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _openPayment(
                                        positiveResourceId(
                                          mapOf(order['wallet_payment'])['id'],
                                        )!,
                                      ),
                                child: const Text('Review wallet payment'),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (orders.isEmpty && payment.isEmpty && ordersAreValid)
                    const Text('No orders recorded.'),
                  if (payment.isEmpty &&
                      ordersPagination != null &&
                      ordersPagination.lastPage > 1)
                    Wrap(
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: _busy || ordersPagination.currentPage <= 1
                              ? null
                              : () => _refresh(
                                  number: ordersPagination.currentPage - 1,
                                ),
                          child: const Text('Previous orders'),
                        ),
                        TextButton(
                          onPressed:
                              _busy ||
                                  ordersPagination.currentPage >=
                                      ordersPagination.lastPage
                              ? null
                              : () => _refresh(
                                  number: ordersPagination.currentPage + 1,
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
