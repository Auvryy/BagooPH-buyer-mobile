import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/application_text_validation.dart';
import '../../core/count_metadata.dart';
import '../../core/resource_ids.dart';
import '../../core/retry_cooldown.dart';
import '../../core/request_id.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _confirmedRequestToken(Object? value) =>
    value is String && _uuidPattern.hasMatch(value) ? value : requestId();

List<Map<String, dynamic>>? _walletRows(Object? value) {
  if (value is! List) return null;
  final rows = <Map<String, dynamic>>[];
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return null;
    rows.add(Map<String, dynamic>.from(row));
  }
  return rows;
}

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

class _WalletSectionState extends BuyerProfileFormState<WalletSection> {
  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  final _amount = TextEditingController(), _reason = TextEditingController();
  late final RetryCooldown _requestCooldown;
  late String _token;
  Map<String, dynamic>? _submitted;
  @override
  void clearBuyerDraft() {
    _requestCooldown.clear(notify: false);
    _submitted = null;
    _amount.clear();
    _reason.clear();
  }

  Map<String, dynamic> get wallet => mapOf(widget.page.props['wallet']);
  List<Map<String, dynamic>>? get _creditRequests {
    final raw = wallet['credit_requests'];
    final rows = _walletRows(raw);
    if (rows == null) return null;
    final ids = <int>{};
    const statuses = {'pending', 'approved', 'rejected'};
    if (rows.any((request) {
      final id = positiveResourceId(request['id']);
      final reference = request['reference'];
      final reason = request['reason'];
      final reviewReason = request['review_reason'];
      final createdAt = strictDateTime(
        request['created_at'],
        requireTimezone: true,
      );
      final reviewedAt = request['reviewed_at'];
      return id == null ||
          !ids.add(id) ||
          !statuses.contains(request['status']) ||
          nonNegativeCount(request['amount_cents']) == null ||
          reference is! String ||
          reference.trim().isEmpty ||
          reason is! String ||
          reason.trim().isEmpty ||
          reviewReason != null && reviewReason is! String ||
          createdAt == null ||
          reviewedAt != null &&
              strictDateTime(reviewedAt, requireTimezone: true) == null;
    })) {
      return null;
    }
    return rows;
  }

  List<Map<String, dynamic>>? get _transactions {
    final raw = mapOf(wallet['transactions'])['data'];
    final rows = _walletRows(raw);
    if (rows == null) return null;
    final ids = <int>{};
    if (rows.any((entry) {
      final id = positiveResourceId(entry['id']);
      final kind = entry['kind'];
      final reference = entry['reference'];
      final delta = entry['delta_cents'];
      final balance = entry['balance_after_cents'];
      final reason = entry['reason'];
      final orderId = entry['order_id'];
      return id == null ||
          !ids.add(id) ||
          kind is! String ||
          kind.trim().isEmpty ||
          reference is! String ||
          reference.trim().isEmpty ||
          delta is! int ||
          nonNegativeCount(balance) == null ||
          reason is! String ||
          reason.trim().isEmpty ||
          strictDateTime(entry['created_at'], requireTimezone: true) == null ||
          orderId != null && positiveResourceId(orderId) == null;
    })) {
      return null;
    }
    return rows;
  }

  bool get _creditRequestsConfirmed => _creditRequests != null;
  bool get pending =>
      _creditRequests?.any((request) => request['status'] == 'pending') ??
      false;
  bool get canRequest =>
      wallet['available'] == true &&
      wallet['can_request'] == true &&
      _creditRequestsConfirmed &&
      !pending;
  @override
  void initState() {
    super.initState();
    _requestCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    _token = _confirmedRequestToken(wallet['request_token']);
  }

  @override
  void dispose() {
    _requestCooldown.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_requestCooldown.active || !canRequest && _submitted == null) return;
    await perform(() async {
      _submitted ??= jsonDecode(
        jsonEncode({
          'request_token': _token,
          'amount': _amount.text.trim(),
          'reason': _reason.text.trim(),
        }),
      ) as Map<String, dynamic>;
      late final Map<String, dynamic> result;
      try {
        result = await widget.repository.json('/wallet/credits', _submitted!);
      } on BackendException catch (error) {
        if (error.status == 429) {
          _requestCooldown.start(
            error.data,
            retryAt: error.retryAt,
            notify: false,
          );
        }
        rethrow;
      }
      checkBuyerAccount();
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
  Widget build(BuildContext context) {
    final creditRequests = _creditRequests;
    final transactions = _transactions;
    final balanceCents = nonNegativeCount(wallet['balance_cents']);
    return content([
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
        wallet['available'] == true && balanceCents != null
            ? pesos(balanceCents / 100)
            : 'Unavailable',
        style: const TextStyle(
          fontSize: 32,
          height: 1.4,
          fontWeight: FontWeight.w800,
          color: BagooTheme.strong,
        ),
      ),
      if (wallet['available'] != true || balanceCents == null)
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
          check: buyerNotesTextError,
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
          label: _requestCooldown.active
              ? 'Retry same request in ${_requestCooldown.remainingSeconds}s'
              : _submitted == null
              ? 'Request credits'
              : 'Retry same credit request',
          busy: busy,
          onPressed:
              _requestCooldown.active || !canRequest && _submitted == null
              ? null
              : _request,
        ),
      ] else
        const Text(
          'An active approved buyer account with a verified email is required to request credits or pay for a new order.',
          style: TextStyle(height: 1.7),
        ),
      if (!_creditRequestsConfirmed)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Notice(
            'Credit request history could not be confirmed. Refresh your wallet before requesting more credits.',
            error: true,
          ),
        ),
      if (creditRequests != null && creditRequests.isNotEmpty) ...[
        const Divider(height: 40),
        const Text(
          'Recent credit requests',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        for (final request in creditRequests)
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
      if (transactions == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Notice(
            'Wallet transaction history could not be confirmed. Refresh your wallet.',
            error: true,
          ),
        )
      else if (transactions.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'No wallet transactions yet. Approved credits, purchases and refunds will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.7),
          ),
        ),
      if (transactions != null)
        for (final entry in transactions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(entry['kind'] as String).replaceAll('_', ' ')} · ${(entry['delta_cents'] as int) >= 0 ? '+' : '−'}${pesos((entry['delta_cents'] as int).abs() / 100)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.7,
                  ),
                ),
                Text(
                  '${readableDateTime(entry['created_at'])}\nBalance ${pesos((entry['balance_after_cents'] as int) / 100)}\n${entry['reference'] ?? 'Reference unavailable'}',
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
                if (positiveResourceId(entry['order_id']) case final orderId?)
                  TextButton(
                    onPressed: () => widget.onOrder(orderId),
                    child: const Text('View order'),
                  ),
                const Divider(),
              ],
            ),
          ),
      if (transactions != null)
        ProfilePagination(
          mapOf(wallet['transactions']),
          widget.onPage,
          disabled: busy,
          pageSize: 10,
        ),
    ]);
  }
}
