import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/request_id.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class WalletSection extends StatefulWidget {
  const WalletSection({
    super.key,
    required this.repository,
    required this.page,
    required this.reload,
    required this.onPage,
    required this.onOrder,
  });
  final ProfileRepository repository;
  final WebPage page;
  final Future<void> Function() reload;
  final ValueChanged<int> onPage, onOrder;
  @override
  State<WalletSection> createState() => _WalletSectionState();
}

class _WalletSectionState extends ProfileFormState<WalletSection> {
  final _amount = TextEditingController(), _reason = TextEditingController();
  late String _token;
  Map<String, dynamic>? _submitted;
  Map<String, dynamic> get wallet => mapOf(widget.page.props['wallet']);
  bool get pending =>
      mapsOf(wallet['credit_requests'])
          .any((request) => request['status'] == 'pending');
  bool get canRequest =>
      wallet['available'] == true && wallet['can_request'] == true && !pending;
  @override
  void initState() {
    super.initState();
    _token = wallet['request_token']?.toString() ?? requestId();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    await perform(() async {
      _submitted ??= jsonDecode(
        jsonEncode({
          'request_token': _token,
          'amount': _amount.text.trim(),
          'reason': _reason.text.trim(),
        }),
      ) as Map<String, dynamic>;
      final result = await widget.repository.json(
        '/wallet/credits',
        _submitted!,
      );
      if (result['reference'] is! String ||
          !['pending', 'approved', 'rejected'].contains(result['status'])) {
        throw const BackendException(
          'Your credit request was not confirmed. Refresh your wallet before retrying.',
        );
      }
      if (mounted) {
        _amount.clear();
        _reason.clear();
        _submitted = null;
        _token = requestId();
      }
      await widget.reload();
      return 'Credit request ${result['reference']} recorded: ${result['status']}. Only approved credits change your balance.';
    });
    if (mounted && errors.isNotEmpty) setState(() => _submitted = null);
  }

  @override
  Widget build(BuildContext context) => content([
    const ProfileHeading(
      'Bagoo Wallet',
      'Virtual credits for purchases inside Bagoo. Admin-approved demo credits have no cash value and cannot be withdrawn or transferred.',
      Icons.account_balance_wallet_outlined,
    ),
    const Text(
      'Available demo credits',
      style: TextStyle(fontSize: 12, height: 1.7, color: BagooTheme.muted),
    ),
    Text(
      wallet['available'] == true && wallet['balance_cents'] != null
          ? pesos((amount(wallet['balance_cents']) ?? 0) / 100)
          : 'Unavailable',
      style: const TextStyle(
        fontSize: 32,
        height: 1.4,
        fontWeight: FontWeight.w800,
        color: BagooTheme.strong,
      ),
    ),
    if (wallet['available'] != true)
      const Notice(
        'Your wallet balance is unavailable. Refresh to review its saved transactions.',
        error: true,
      ),
    const Divider(height: 40),
    if (wallet['can_request'] == true) ...[
      const Text(
        'Request demo credits',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'An admin reviews the amount and reason. Requesting credits does not increase your balance.',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
      ),
      if (pending)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Notice('Your current request is awaiting admin review.'),
        ),
      field(
        'amount',
        'Amount (PHP)',
        _amount,
        enabled: canRequest && _submitted == null,
        max: 9,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        hint: '₱1.00–₱100,000.00 per request.',
        check: (v) {
          final valid = RegExp(r'^[0-9]{1,6}(\.[0-9]{1,2})?$').hasMatch(v);
          final value = amount(v);
          return valid && value != null && value >= 1 && value <= 100000
              ? null
              : 'Request between ₱1.00 and ₱100,000.00.';
        },
      ),
      field(
        'reason',
        'Reason',
        _reason,
        enabled: canRequest && _submitted == null,
        min: 5,
        max: 500,
        lines: 3,
      ),
      if (_submitted != null)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Notice(
            'The last response is uncertain. Review your recent requests before retrying the same request.',
            error: true,
          ),
        ),
      SubmitButton(
        label: _submitted == null
            ? 'Request credits'
            : 'Retry same credit request',
        busy: busy,
        onPressed: !canRequest && _submitted == null ? null : _request,
      ),
    ] else
      const Text(
        'An active approved buyer account with a verified email is required to request credits or pay for a new order.',
        style: TextStyle(height: 1.7),
      ),
    if (mapsOf(wallet['credit_requests']).isNotEmpty) ...[
      const Divider(height: 40),
      const Text(
        'Recent credit requests',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      for (final request in mapsOf(wallet['credit_requests']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${pesos((amount(request['amount_cents']) ?? 0) / 100)} · ${request['status']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.7,
                ),
              ),
              Text(
                request['reference']?.toString() ?? '',
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
              Text(
                readableDateTime(request['created_at']),
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
              if (request['review_reason'] != null)
                Text(
                  'Admin feedback: ${request['review_reason']}',
                  style: const TextStyle(fontSize: 13, height: 1.7),
                ),
            ],
          ),
        ),
    ],
    const Divider(height: 40),
    const Text(
      'Transactions',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
    if (mapsOf(mapOf(wallet['transactions'])['data']).isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'No wallet transactions yet. Approved credits, purchases and refunds will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.7),
        ),
      ),
    for (final entry in mapsOf(mapOf(wallet['transactions'])['data']))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry['kind'].toString().replaceAll('_', ' ')} · ${(amount(entry['delta_cents']) ?? 0) >= 0 ? '+' : '−'}${pesos((amount(entry['delta_cents']) ?? 0).abs() / 100)}',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.7),
            ),
            Text(
              '${readableDateTime(entry['created_at'])}\nBalance ${pesos((amount(entry['balance_after_cents']) ?? 0) / 100)}\n${entry['reference']}',
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
            if (entry['order_id'] is num)
              TextButton(
                onPressed: () =>
                    widget.onOrder((entry['order_id'] as num).toInt()),
                child: const Text('View order'),
              ),
            const Divider(),
          ],
        ),
      ),
    ProfilePagination(
      mapOf(wallet['transactions']),
      widget.onPage,
      disabled: busy,
    ),
  ]);
}
