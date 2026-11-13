import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/count_metadata.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class ShipmentFinancePage extends StatefulWidget {
  const ShipmentFinancePage({
    super.key,
    required this.repository,
    required this.initial,
    this.account,
  });

  final ProfileRepository repository;
  final WebPage initial;
  final BuyerAccountScope? account;

  @override
  State<ShipmentFinancePage> createState() => _ShipmentFinancePageState();
}

class _ShipmentFinancePageState extends State<ShipmentFinancePage> {
  late WebPage _page = widget.initial;
  late final BuyerAccountScope _account =
      widget.account ??
      (BuyerAccountScope(widget.repository.session)..check(page: _page));
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _plan =>
      mapOf(_page.props['financialPlan'] ?? _page.props['plan']);
  Map<String, dynamic> get _amounts => mapOf(_plan['amounts']);
  Map<String, dynamic> get _state => mapOf(_plan['state']);
  List<String> get _actions =>
      (_plan['actions'] is List ? _plan['actions'] as List : const [])
          .whereType<String>()
          .toList();
  List<Map<String, dynamic>> get _history => mapsOf(_plan['history']);

  String _money(Object? centsValue) {
    final value = nonNegativeCount(centsValue);
    return value == null ? '₱0.00' : pesos(value / 100);
  }

  @override
  void initState() {
    super.initState();
    final remaining = nonNegativeCount(_state['remaining_cents']);
    if (remaining != null && remaining > 0) {
      _amount.text = (remaining / 100).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _payWalletShipping() async {
    final planId = positiveResourceId(_plan['id']);
    final version = nonNegativeCount(_plan['version']);
    if (_busy || planId == null || version == null) return;
    final trimmedReason = _reason.text.trim();
    if (trimmedReason.length < 10) {
      setState(() => _error = 'Enter at least 10 characters for your reason.');
      return;
    }
    if (!_confirmed) {
      setState(
        () => _error = 'Confirm the virtual credit shipping payment first.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await widget.repository.session.submit(
        '/shipment-finances/$planId/actions',
        {
          'action': 'pay-wallet-shipping',
          'expected_version': version,
          'request_token': 'mob-${DateTime.now().microsecondsSinceEpoch}',
          'amount': _amount.text.trim(),
          'reason': trimmedReason,
          'payment_confirmed': true,
        },
        referer: '/shipment-finances/$planId',
      );
      widget.repository.buyer.requireNoErrors(next);
      _account.check(page: next);
      if (!mounted) return;
      setState(() {
        _page = next;
        _confirmed = false;
        _reason.clear();
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderNumber =
        mapOf(_plan['order'])['order_number']?.toString() ?? 'Order';
    final reference = _plan['reference']?.toString() ?? 'Shipment Plan';
    final status = _plan['status']?.toString().replaceAll('_', ' ') ?? 'open';
    final mode = _plan['mode']?.toString() ?? 'cod';
    final canPayWallet = _actions.contains('pay-wallet-shipping');

    return Scaffold(
      appBar: AppBar(title: const Text('Shipping & refund outcome')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Notice(_error!, error: true),
                    const SizedBox(height: 12),
                  ],
                  ProfilePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfileHeading(
                          'Shipping and refund · $orderNumber',
                          '$reference · Status: $status',
                          Icons.receipt_long_outlined,
                        ),
                        Text(
                          mode == 'wallet'
                              ? 'Demonstration Wallet credits'
                              : 'COD not collected · no merchandise refund',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: BagooTheme.crimson,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Merchandise refund: ${_money(_amounts['buyer_merchandise_refund_cents'] ?? _amounts['merchandise_refund_cents'])}\n'
                          'Assessed shipping due: ${_money(_state['due_cents'] ?? _amounts['buyer_shipping_due_cents'])}\n'
                          'Shipping payments received: ${_money(_state['received_cents'])}\n'
                          'Remaining shipping balance: ${_money(_state['remaining_cents'])}',
                          style: const TextStyle(height: 1.75),
                        ),
                        if (_plan['wallet_balance_cents'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Available Bagoo Wallet credits: ${_money(_plan['wallet_balance_cents'])}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: BagooTheme.ink,
                            ),
                          ),
                        ],
                        if (_plan['review_reason'] is String &&
                            (_plan['review_reason'] as String)
                                .trim()
                                .isNotEmpty) ...[
                          const Divider(height: 24),
                          Text(
                            'Independent review: ${_plan['review_reason']}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: BagooTheme.muted,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canPayWallet)
                    ProfilePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ProfileHeading(
                            'Pay shipping from Bagoo Wallet',
                            'Settle the assessed refusal shipping balance using your virtual Wallet credits.',
                            Icons.account_balance_wallet_outlined,
                          ),
                          TextField(
                            controller: _amount,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Virtual credits to pay (PHP)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _reason,
                            enabled: !_busy,
                            maxLines: 3,
                            maxLength: 1000,
                            decoration: const InputDecoration(
                              labelText: 'Reason or payment details',
                            ),
                          ),
                          CheckboxListTile(
                            value: _confirmed,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: _busy
                                ? null
                                : (v) =>
                                      setState(() => _confirmed = v ?? false),
                            title: const Text(
                              'Pay the entered shipping amount from my available virtual credits.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _busy ? null : _payWalletShipping,
                            child: Text(
                              _busy ? 'Saving…' : 'Pay shipping from my Wallet',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_history.isNotEmpty)
                    ProfilePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ProfileHeading(
                            'Financial history',
                            'Recorded shipping and refund events.',
                            Icons.history,
                          ),
                          for (final event in _history)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                '${event['event_type']?.toString().replaceAll('-', ' ') ?? 'Update'} · ${readableDateTime(event['created_at'])}\n'
                                '${_money(event['amount_cents'])}'
                                '${event['reason'] != null ? '\n${event['reason']}' : ''}',
                                style: const TextStyle(height: 1.65),
                              ),
                            ),
                        ],
                      ),
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
