import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/application_text_validation.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/web_session.dart';
import '../../core/foreground_refresh.dart';
import '../../core/retry_cooldown.dart';
import '../../core/resource_ids.dart';
import '../../core/strict_datetime.dart';
import '../../core/widgets.dart';
import '../../core/uploads.dart';
import '../home/product_card.dart';
import '../products/product_widgets.dart';
import 'profile_widgets.dart';
import 'profile_repository.dart';
import 'purchases_section.dart';
import 'returns_page.dart';
import 'shipment_finance_page.dart';
import 'order_journey.dart';
import '../checkout/commerce_details.dart';
import '../engagement/engagement_repository.dart';

List<Map<String, dynamic>>? _completeBuyerReturns(Object? raw) {
  if (raw is! List) return null;
  final rows = <Map<String, dynamic>>[];
  final ids = <int>{};
  for (final row in raw) {
    if (row is! Map || row.keys.any((key) => key is! String)) return null;
    final item = Map<String, dynamic>.from(row);
    final id = positiveResourceId(item['id']);
    final reference = item['reference'];
    final status = item['status'];
    if (id == null ||
        !ids.add(id) ||
        reference is! String ||
        reference.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty) {
      return null;
    }
    rows.add(item);
  }
  return rows;
}

bool _returnRequestIsConfirmed(Object? raw) {
  if (raw is! Map || raw.keys.any((key) => key is! String)) return false;
  final availability = Map<String, dynamic>.from(raw);
  final until = strictDateTime(availability['until']);
  return availability['can_request'] == true &&
      availability['reason'] == null &&
      until != null &&
      until.isAfter(DateTime.now());
}

List<String>? _completeCancellationReasons(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final reasons = <String>[];
  final seen = <String>{};
  for (final reason in raw) {
    if (reason is! String || reason.trim().isEmpty || !seen.add(reason)) {
      return null;
    }
    reasons.add(reason);
  }
  return reasons;
}

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.repository,
    required this.orderId,
  });
  final ProfileRepository repository;
  final int orderId;
  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ProfileFormState<OrderDetailPage> {
  WebPage? _page;
  String? _code;
  Timer? _claimTimer;
  late BuyerAccountScope _account;
  late ForegroundRead _updates;
  late RetryCooldown _pickupCooldown;
  late int _identityEpoch;
  String? _updateError;
  bool _refreshing = true, _accessLost = false, _manualRefresh = false;
  bool _confirmingReceipt = false, _confirmingPickup = false;
  bool _pickupWasRateLimited = false;
  Map<String, dynamic> get order => mapOf(_page?.props['order']);
  Map<String, dynamic> get claim => mapOf(_page?.props['pickupClaim']);
  bool get hasCurrentAccount =>
      !_accessLost &&
      _account.isCurrent &&
      identical(_account.session, widget.repository.session) &&
      _identityEpoch == widget.repository.session.identityEpoch;

  bool _ensureCurrentAccount() {
    if (hasCurrentAccount) return true;
    if (mounted && !_accessLost) {
      setState(() {
        _clearPrivate();
        problem = 'Your account changed. Reopen this order after signing in.';
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    _identityEpoch = widget.repository.session.identityEpoch;
    _account = BuyerAccountScope(widget.repository.session);
    _updates = ForegroundRead(read: _read);
    _pickupCooldown = RetryCooldown(() {
      if (mounted) {
        setState(() {
          if (!_pickupCooldown.active && _pickupWasRateLimited) {
            _pickupWasRateLimited = false;
            problem = null;
            errors = {};
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant OrderDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.orderId != widget.orderId) {
      _updates.dispose();
      _account.invalidate();
      _pickupCooldown.dispose();
      _claimTimer?.cancel();
      _page = null;
      _code = _updateError = problem = success = null;
      errors = {};
      _accessLost = _manualRefresh = false;
      _pickupWasRateLimited = false;
      _refreshing = true;
      _configure();
    }
  }

  @override
  void dispose() {
    _updates.dispose();
    _account.invalidate();
    _pickupCooldown.dispose();
    _claimTimer?.cancel();
    _code = null;
    super.dispose();
  }

  bool get readyForPickup {
    final expiry = strictDateTime(claim['expires_at']);
    final locked = strictDateTime(claim['locked_until']);
    return claim['status'] == 'ready' &&
        expiry != null &&
        expiry.isAfter(DateTime.now()) &&
        (claim['locked_until'] == null ||
            locked != null && !locked.isAfter(DateTime.now()));
  }

  bool _pickupClaimCurrent(String reference, int epoch) =>
      hasCurrentAccount &&
      epoch == _identityEpoch &&
      widget.repository.session.identityEpoch == epoch &&
      _page?.props['pickupCodeAvailable'] == true &&
      claim['reference'] == reference &&
      readyForPickup &&
      claim['code_issued_at'] == null &&
      _code == null;

  void _accept(WebPage page) {
    widget.repository.buyer.requireNoErrors(page);
    if (_identityEpoch != widget.repository.session.identityEpoch) {
      throw const BackendException(
        'This order could not be confirmed for your account.',
        status: 401,
      );
    }
    _account.check(page: page);
    final rawOrder = page.props['order'];
    if (rawOrder is! Map) {
      throw const BackendException(
        'Order details could not be confirmed. Refresh this order.',
      );
    }
    requireRowsWithIds(
      rawOrder['items'],
      idKey: 'id',
      error: 'Purchased items could not be confirmed. Refresh this order.',
    );
    if (page.component != 'Buyer/OrderDetail' ||
        mapOf(rawOrder)['id'] != widget.orderId ||
        positiveResourceId(page.user?['id']) == null ||
        page.user?['role'] != 'buyer' ||
        _page != null && _page!.user?['id'] != page.user?['id']) {
      throw const BackendException(
        'This order could not be confirmed for your account.',
        status: 401,
      );
    }
    if (!mounted) return;
    final prior = claim['reference'];
    setState(() {
      _page = page;
      if (prior != claim['reference'] || !readyForPickup) _code = null;
    });
    _scheduleClaimBoundary();
  }

  void _scheduleClaimBoundary() {
    _claimTimer?.cancel();
    final boundaries =
        [claim['expires_at'], claim['locked_until']]
            .map(strictDateTime)
            .whereType<DateTime>()
            .where((v) => v.isAfter(DateTime.now()))
            .toList()
          ..sort();
    if (boundaries.isNotEmpty) {
      _claimTimer = Timer(
        boundaries.first.difference(DateTime.now()) +
            const Duration(milliseconds: 100),
        () {
          if (mounted) {
            setState(() {
              if (!readyForPickup) _code = null;
            });
            _scheduleClaimBoundary();
          }
        },
      );
    }
  }

  void _clearPrivate() {
    _accessLost = true;
    _account.invalidate();
    _updates.setActive(false);
    _claimTimer?.cancel();
    _page = null;
    _code = null;
    success = null;
    errors = {};
    _refreshing = false;
  }

  @override
  void onFailure(BackendException error) {
    if (_confirmingPickup && error.status == 429) {
      _pickupWasRateLimited = true;
      _pickupCooldown.start(error.data, retryAt: error.retryAt, notify: false);
    }
    if ([401, 403, 404, 419].contains(error.status) ||
        _identityEpoch != widget.repository.session.identityEpoch) {
      _clearPrivate();
    }
  }

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (!mounted) return Future.value(false);
    if (!_ensureCurrentAccount()) {
      return Future.value(false);
    }
    _updates.setActive(false);
    return super.perform(() async {
      final result = await action();
      _account.check();
      return result;
    }, validate: validate);
  }

  Future<void> _load() async {
    _manualRefresh = true;
    await _updates.refresh();
  }

  Future<ReadOutcome> _read(ReadTicket ticket) async {
    final clearActionError = _manualRefresh;
    _manualRefresh = false;
    if (mounted) setState(() => _refreshing = true);
    try {
      if (_identityEpoch != widget.repository.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Reopen this order after signing in.',
          status: 401,
        );
      }
      final page = await widget.repository.session.page(
        '/buyer/orders/${widget.orderId}',
      );
      if (!mounted || !ticket.isCurrent) return ReadOutcome.success;
      _accept(page);
      setState(() {
        _updateError = null;
        if (clearActionError) {
          _pickupWasRateLimited = false;
          problem = null;
          errors = {};
        }
      });
      return ReadOutcome.success;
    } on BackendException catch (e) {
      if (!mounted || !ticket.isCurrent) return ReadOutcome.success;
      final denied =
          [401, 403, 404, 419].contains(e.status) ||
          _identityEpoch != widget.repository.session.identityEpoch;
      setState(() {
        _updateError = denied
            ? e.message
            : 'Order updates are delayed. Retrying automatically. ${e.message}';
        if (denied) _clearPrivate();
      });
      return denied ? ReadOutcome.stop : ReadOutcome.retry;
    } catch (_) {
      if (mounted && ticket.isCurrent) {
        setState(
          () => _updateError =
              'Order updates are delayed. Retrying automatically.',
        );
      }
      return ReadOutcome.retry;
    } finally {
      if (mounted && ticket.isCurrent) setState(() => _refreshing = false);
    }
  }

  Future<void> _confirm() async {
    if (!mounted || _confirmingReceipt || busy) return;
    if (!_ensureCurrentAccount()) return;
    final openingPage = _page;
    if (openingPage == null ||
        openingPage.props['canConfirmReceipt'] != true ||
        mapOf(openingPage.props['order'])['id'] != widget.orderId ||
        completePurchaseItems(mapOf(openingPage.props['order'])['items']) ==
            null) {
      return;
    }
    final openingEpoch = _identityEpoch;
    final orderNumber = mapOf(openingPage.props['order'])['order_number'];
    _confirmingReceipt = true;
    setState(() {});
    try {
      if (!await confirmAction(
            context,
            'Confirm receipt?',
            'Confirm that you received order #$orderNumber and checked its items. This records your receipt and completes the purchase.',
            'Confirm Received',
          ) ||
          !mounted) {
        return;
      }

      if (!_ensureCurrentAccount()) return;
      final currentPage = _page;
      if (openingEpoch != widget.repository.session.identityEpoch ||
          currentPage == null ||
          currentPage.component != 'Buyer/OrderDetail' ||
          currentPage.props['canConfirmReceipt'] != true ||
          mapOf(currentPage.props['order'])['id'] != widget.orderId ||
          completePurchaseItems(mapOf(currentPage.props['order'])['items']) ==
              null ||
          currentPage.user?['role'] != 'buyer' ||
          positiveResourceId(currentPage.user?['id']) == null) {
        if (mounted &&
            openingEpoch != widget.repository.session.identityEpoch) {
          setState(() {
            _clearPrivate();
            problem =
                'Your account changed. Reopen this order after signing in.';
          });
        }
        return;
      }

      await perform(() async {
        final page = await widget.repository.session.submit(
          '/buyer/orders/${widget.orderId}/confirm',
          {},
          referer: '/buyer/orders/${widget.orderId}',
        );
        _accept(page);
        if (order['status'] != 'completed') {
          throw const BackendException(
            'Receipt confirmation was not confirmed. Refresh the order before trying again.',
          );
        }
        return mapOf(page.props['flash'])['success']?.toString() ??
            'Receipt confirmed.';
      }, validate: false);
    } finally {
      if (mounted) setState(() => _confirmingReceipt = false);
    }
  }

  Future<void> _pickup() async {
    if (!mounted ||
        _confirmingPickup ||
        _pickupCooldown.active ||
        !_ensureCurrentAccount()) {
      return;
    }
    final reference = claim['reference'];
    final epoch = _identityEpoch;
    if (reference is! String ||
        reference.isEmpty ||
        !_pickupClaimCurrent(reference, epoch)) {
      return;
    }
    _confirmingPickup = true;
    setState(() {});
    try {
      if (!await confirmAction(
            context,
            'Show your private pickup code?',
            'This code is shown once. Keep it private and save it when it appears; it cannot be revealed again.',
            'Show my code once',
          ) ||
          !mounted) {
        return;
      }
      if (!_ensureCurrentAccount()) return;
      if (!_pickupClaimCurrent(reference, epoch)) {
        setState(
          () => problem = 'Pickup status changed. Refresh tracking before requesting a code.',
        );
        return;
      }
      await perform(() async {
        if (!_pickupClaimCurrent(reference, epoch)) {
          throw const BackendException(
            'Pickup status changed. Refresh tracking before requesting a code.',
          );
        }
        final data = await widget.repository.json(
          '/buyer/orders/${widget.orderId}/pickup-code',
          {},
        );
        final code = data['code'];
        if (code is! String || !RegExp(r'^[A-F0-9]{12}$').hasMatch(code)) {
          throw const BackendException(
            'The pickup code was not returned in a usable format. Refresh tracking before trying again.',
          );
        }
        if (mounted &&
            hasCurrentAccount &&
            epoch == widget.repository.session.identityEpoch &&
            claim['reference'] == reference) {
          setState(() => _code = code);
        }
        return 'Keep your code private. Present it with your valid photo ID at the assigned hub.';
      }, validate: false);
    } finally {
      if (mounted) {
        _confirmingPickup = false;
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = mapOf(order['tracking']);
    final orderItems = completePurchaseItems(order['items']);
    final buyerReturns = _completeBuyerReturns(_page?.props['buyerReturns']);
    final canRequestReturn = _returnRequestIsConfirmed(
      _page?.props['returnAvailability'],
    );
    final orderNotices = completeBuyerOrderNotices(
      _page?.props['orderNotices'],
    );
    final userCan = _page?.props['canUsePortal'] == true;
    final canAct =
        !busy &&
        !_confirmingReceipt &&
        !_confirmingPickup &&
        hasCurrentAccount &&
        problem == null &&
        _updateError == null;
    return ForegroundRefresh(
      controller: _updates,
      enabled: !busy && !_accessLost,
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              order.isEmpty
                  ? 'Your purchase'
                  : 'Order #${order['order_number']}',
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh recorded order',
                onPressed: busy || _refreshing || _accessLost ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (busy || _refreshing && _page == null)
                      const LinearProgressIndicator(),
                    if (_updateError != null) ...[
                      Notice(_updateError!, error: true),
                      if (!_accessLost)
                        TextButton(
                          onPressed: _refreshing ? null : _load,
                          child: const Text('Refresh order'),
                        ),
                    ],
                    if (problem != null) ...[
                      Notice(
                        [problem!, ...errors.values].join('\n'),
                        error: true,
                      ),
                      TextButton(
                        onPressed: busy || _accessLost ? null : _load,
                        child: const Text('Refresh order'),
                      ),
                    ],
                    if (success != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Notice(success!),
                      ),
                    if (_page != null && !hasCurrentAccount)
                      const Notice(
                        'Your account changed. Reopen this order after signing in.',
                        error: true,
                      ),
                    if (_page != null && hasCurrentAccount) ...[
                      ProfilePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ProfileHeading(
                              'Order progress',
                              'Placed ${readableDateTime(order['created_at'])}. Status reflects recorded parcel checkpoints.',
                              Icons.local_shipping_outlined,
                            ),
                            Text(
                              tracking['status_label']?.toString() ??
                                  order['status']?.toString() ??
                                  'Status not loaded',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: BagooTheme.strong,
                                height: 1.5,
                              ),
                            ),
                            Text(
                              tracking['stage_label']?.toString() ??
                                  'Parcel stage not loaded',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                height: 1.7,
                              ),
                            ),
                            Text(
                              'Recorded holder: ${tracking['custodian'] ?? 'Not recorded'}\n${tracking['responsible'] ?? 'Next step'}: ${tracking['next_step'] ?? 'Refresh for the next recorded step.'}',
                              style: const TextStyle(height: 1.7),
                            ),
                            if (tracking['notice'] != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Notice(tracking['notice'].toString()),
                              ),
                            if (tracking['failure'] is Map)
                              Text(
                                'Delivery attempt: ${mapOf(tracking['failure'])['reason']}\n${readableDateTime(mapOf(tracking['failure'])['attempted_at'])}${mapOf(tracking['failure'])['retry_at'] == null ? '' : '\nApproved retry: ${readableDateTime(mapOf(tracking['failure'])['retry_at'])}'}',
                                style: const TextStyle(height: 1.7),
                              ),
                            if ((amount(order['logistics_flow_version']) ??
                                    1) >=
                                2)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'Automatic completion: Orders under Logistics Flow v2 complete automatically after verified doorstep POD or Bayan Hub collection.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: BagooTheme.muted,
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_page!.props['canConfirmReceipt'] == true)
                                  FilledButton(
                                    onPressed: canAct && orderItems != null
                                        ? _confirm
                                        : null,
                                    child: const Text('Confirm Received'),
                                  ),
                                if (userCan &&
                                    _page!.props['buyAgainToken'] is String)
                                  OutlinedButton(
                                    onPressed: canAct
                                        ? () => perform(() async {
                                            await buyAgain(
                                              context,
                                              widget.repository,
                                              widget.orderId,
                                              _page!.props['buyAgainToken'],
                                              parentAccount: _account,
                                            );
                                            return null;
                                          }, validate: false)
                                        : null,
                                    child: const Text('Buy again'),
                                  ),
                                if (_page!.props['cancelOrderUrl'] is String)
                                  OutlinedButton(
                                    onPressed: canAct
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => _CancelOrderPage(
                                                repository: widget.repository,
                                                page: _page!,
                                                account: _account,
                                                onSaved: _accept,
                                              ),
                                            ),
                                          )
                                        : null,
                                    child: const Text('Cancel order'),
                                  )
                                else if (_page!.props['cancellationRequestUrl']
                                    is String)
                                  OutlinedButton(
                                    onPressed: canAct
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => _CancelOrderPage(
                                                repository: widget.repository,
                                                page: _page!,
                                                account: _account,
                                                onSaved: _accept,
                                                isRequest: true,
                                              ),
                                            ),
                                          )
                                        : null,
                                    child: const Text('Request cancellation'),
                                  ),
                                if (canRequestReturn)
                                  OutlinedButton(
                                    onPressed: canAct
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => ReturnsPage(
                                                repository: widget.repository,
                                                orderId: widget.orderId,
                                                account: _account,
                                              ),
                                            ),
                                          )
                                        : null,
                                    child: const Text('Request return/refund'),
                                  ),
                                if (positiveResourceId(
                                      mapOf(
                                        _page!.props['shipmentFinance'],
                                      )['id'],
                                    )
                                    case final financeId?)
                                  OutlinedButton(
                                    onPressed: canAct
                                        ? () => perform(() async {
                                            final financePage = await widget
                                                .repository
                                                .buyer
                                                .document(
                                                  '/shipment-finances/$financeId',
                                                );
                                            widget.repository.buyer
                                                .requireNoErrors(financePage);
                                            _account.check(page: financePage);
                                            if (context.mounted) {
                                              await Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      ShipmentFinancePage(
                                                        repository:
                                                            widget.repository,
                                                        initial: financePage,
                                                        account: _account,
                                                      ),
                                                ),
                                              );
                                              _accept(
                                                await widget.repository.order(
                                                  widget.orderId,
                                                ),
                                              );
                                            }
                                            return null;
                                          }, validate: false)
                                        : null,
                                    child: const Text(
                                      'Review shipping balance',
                                    ),
                                  ),
                                if (positiveResourceId(
                                      mapOf(order['wallet_payment'])['id'],
                                    )
                                    case final paymentId?)
                                  TextButton(
                                    onPressed: canAct
                                        ? () => perform(() async {
                                            await openWalletPayment(
                                              context,
                                              widget.repository,
                                              paymentId,
                                              parentAccount: _account,
                                            );
                                            _accept(
                                              await widget.repository.order(
                                                widget.orderId,
                                              ),
                                            );
                                            return null;
                                          }, validate: false)
                                        : null,
                                    child: const Text('Review wallet payment'),
                                  ),
                              ],
                            ),
                            if (_page!.props['cancellationReason'] != null)
                              Text(
                                'Cancellation reason: ${_page!.props['cancellationReason']}',
                                style: const TextStyle(height: 1.7),
                              ),
                            if (_page!.props['cancellationFeedback'] is Map)
                              _cancellationFeedbackSection(
                                mapOf(_page!.props['cancellationFeedback']),
                              ),
                          ],
                        ),
                      ),
                      if (claim.isNotEmpty)
                        ProfilePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProfileHeading(
                                'Bayan Hub collection',
                                'Bring your valid photo ID. COD parcels require the recorded cash payment; a paid wallet parcel requires no cash.',
                                Icons.storefront_outlined,
                              ),
                              Text(
                                '${mapOf(_page!.props['pickupHub'])['name'] ?? 'Assigned hub'}\n${mapOf(_page!.props['pickupHub'])['address'] ?? ''}\n${mapOf(_page!.props['pickupHub'])['operating_hours'] ?? 'Contact the hub for operating hours.'}\nCollect before: ${readableDateTime(claim['expires_at'])}',
                                style: const TextStyle(height: 1.7),
                              ),
                              if (_code != null && readyForPickup)
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: SelectableText(
                                    _code!,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (_code == null &&
                                  claim['code_issued_at'] != null)
                                const Text(
                                  'Your code was already shown. Use the code you saved; contact the hub if it was lost.',
                                  style: TextStyle(height: 1.7),
                                ),
                              if (readyForPickup &&
                                  _page!.props['pickupCodeAvailable'] == true &&
                                  claim['code_issued_at'] == null &&
                                  _code == null)
                                FilledButton(
                                  onPressed: canAct && !_pickupCooldown.active
                                      ? _pickup
                                      : null,
                                  child: Text(
                                    _pickupCooldown.active
                                        ? 'Try again in ${_pickupCooldown.remainingSeconds}s'
                                        : 'Show my code once',
                                  ),
                                ),
                              if (!readyForPickup)
                                Text(
                                  'Collection status: ${claim['status']}. Refresh tracking to check current collection authority. ${claim['locked_until'] == null ? '' : 'Locked until ${readableDateTime(claim['locked_until'])}.'}',
                                  style: const TextStyle(height: 1.7),
                                ),
                            ],
                          ),
                        ),
                      ProfilePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const ProfileHeading(
                              'Purchased items',
                              'Original item options, quantities, and recorded prices.',
                              Icons.shopping_bag_outlined,
                            ),
                            if (orderItems == null)
                              const Notice(
                                'Purchased item details could not be confirmed. Refresh this order before confirming receipt.',
                                error: true,
                              )
                            else
                              for (final item in orderItems) ...[
                                OrderItemSummary(
                                  item: item,
                                  session: widget.repository.session,
                                  repository: widget.repository.buyer,
                                ),
                                if (item['review'] is Map)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      'Your rating: ${mapOf(item['review'])['rating']} / 5\n${mapOf(item['review'])['comment'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.7,
                                      ),
                                    ),
                                  ),
                                if (userCan &&
                                    order['status'] == 'completed' &&
                                    (item['review'] == null ||
                                        mapOf(item['review'])['edit_url']
                                            is String))
                                  TextButton.icon(
                                    onPressed: canAct
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => _ReviewPage(
                                                repository: widget.repository,
                                                item: item,
                                                orderId: widget.orderId,
                                                account: _account,
                                                onSaved: _accept,
                                              ),
                                            ),
                                          )
                                        : null,
                                    icon: const Icon(Icons.star_outline),
                                    label: Text(
                                      item['review'] == null
                                          ? 'Rate & review purchased item'
                                          : 'Edit your review',
                                    ),
                                  ),
                                const Divider(height: 24),
                              ],
                            Text(
                              'Subtotal: ${pesos(order['subtotal'])}\nDelivery: ${pesos(order['shipping_fee'])}\nDiscount: ${pesos(order['voucher_discount'])}\nTotal: ${pesos(order['total_amount'])}\nPayment: ${order['payment_method']} · ${order['payment_status']}',
                              style: const TextStyle(
                                height: 1.8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (order['voucher_receipt'] is Map)
                        ProfilePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProductHeading('Original voucher receipt'),
                              VoucherReceipt(
                                receipt: mapOf(order['voucher_receipt']),
                                paymentMethod:
                                    order['payment_method']?.toString() ??
                                    'cod',
                              ),
                            ],
                          ),
                        ),
                      if (order['delivery'] is Map)
                        ProfilePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ProductHeading('Package details'),
                              for (final entry in const {
                                'tracking_number': 'Tracking number',
                                'logistics_partner': 'Logistics partner',
                                'pickup_store_name': 'Pickup shop',
                                'pickup_address': 'Pickup address',
                                'delivery_recipient_name': 'Recipient',
                                'delivery_address': 'Delivery address',
                                'courier_notes': 'Courier notes',
                              }.entries)
                                if (mapOf(order['delivery'])[entry.key] != null)
                                  Text(
                                    '${entry.value}: ${mapOf(order['delivery'])[entry.key]}',
                                    style: const TextStyle(height: 1.7),
                                  ),
                              if (mapOf(
                                    mapOf(order['delivery'])['courier'],
                                  )['name'] !=
                                  null)
                                Text(
                                  'Courier: ${mapOf(mapOf(order['delivery'])['courier'])['name']}',
                                  style: const TextStyle(height: 1.7),
                                ),
                            ],
                          ),
                        ),
                      ProfilePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const ProfileHeading(
                              'Delivery recipient',
                              'Existing orders retain the delivery details recorded at checkout.',
                              Icons.location_on_outlined,
                            ),
                            Text(
                              '${order['recipient_name'] ?? order['shipping_name'] ?? 'Not recorded'}\n${order['recipient_phone'] ?? order['shipping_phone'] ?? ''}\n${order['shipping_address'] ?? ''}\n${order['destination_barangay'] ?? ''}, ${order['shipping_city'] ?? ''}, ${order['shipping_province'] ?? ''} ${order['shipping_postal_code'] ?? ''}',
                              style: const TextStyle(height: 1.8),
                            ),
                          ],
                        ),
                      ),
                      if (buyerReturns == null)
                        const ProfilePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ProfileHeading(
                                'Returns & Refunds',
                                '',
                                Icons.assignment_return_outlined,
                              ),
                              Notice(
                                'Return details could not be confirmed. Refresh this order to check again.',
                                error: true,
                              ),
                            ],
                          ),
                        )
                      else if (buyerReturns.isNotEmpty)
                        ProfilePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProfileHeading(
                                'Returns & Refunds',
                                '',
                                Icons.assignment_return_outlined,
                              ),
                              for (final item in buyerReturns)
                                ListTile(
                                  title: Text(item['reference'].toString()),
                                  subtitle: Text(item['status'].toString()),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: positiveResourceId(item['id']) == null
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => ReturnsPage(
                                              repository: widget.repository,
                                              caseId: positiveResourceId(
                                                item['id'],
                                              )!,
                                              account: _account,
                                            ),
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ),
                      ProfilePanel(
                        child: OrderJourney(
                          order: order,
                          notices: orderNotices ?? const [],
                          noticesAvailable: orderNotices != null,
                          busy: busy,
                          onRead: (id) => perform(() async {
                            await BuyerEngagementRepository(
                              widget.repository.buyer,
                            ).markNotificationRead(id);
                            _accept(
                              await widget.repository.order(widget.orderId),
                            );
                            return 'Order update marked read.';
                          }, validate: false),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cancellationFeedbackSection(Map<String, dynamic> feedback) {
    final request = mapOf(feedback['request']);
    final refund = mapOf(feedback['refund']);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BagooTheme.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BagooTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cancellation update',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: BagooTheme.strong,
              ),
            ),
            if (feedback['message'] != null) ...[
              const SizedBox(height: 4),
              Text(
                feedback['message'].toString(),
                style: const TextStyle(height: 1.6),
              ),
            ],
            if (request.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${request['reference'] ?? 'Request'} · ${request['status'] ?? 'pending'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
              if (request['respond_by'] != null)
                Text(
                  'Seller response due ${readableDateTime(request['respond_by'])}',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              if (request['decision_reason'] != null)
                Text(
                  'Review outcome: ${request['decision_reason']}',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
            ],
            if (feedback['payment_message'] != null) ...[
              const SizedBox(height: 6),
              Text(
                feedback['payment_message'].toString(),
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
            if (refund.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Wallet refund: ${pesos((amount(refund['amount_cents']) ?? 0) / 100)}${refund['reference'] == null ? '' : ' · ${refund['reference']}'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

abstract class _OrderAccountFormState<T extends StatefulWidget>
    extends ProfileFormState<T>
    with WidgetsBindingObserver {
  ProfileRepository get repository;
  BuyerAccountScope get parentAccount;
  void clearPrivateDraft();

  late final BuyerAccountScope accountScope;
  bool get hasOrderAccount =>
      accountScope.isCurrent &&
      identical(accountScope.session, repository.session);

  @override
  void initState() {
    super.initState();
    accountScope = parentAccount.fork();
    WidgetsBinding.instance.addObserver(this);
  }

  void _discardOrderAccount() {
    accountScope.invalidate();
    clearPrivateDraft();
    errors = {};
    success = null;
    problem = 'Your buyer account changed or access ended. Reopen this order from your purchases.';
  }

  bool ensureOrderAccount() {
    if (hasOrderAccount) return true;
    if (mounted) setState(_discardOrderAccount);
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ensureOrderAccount();
  }

  @override
  void onFailure(BackendException error) {
    if (!hasOrderAccount || [401, 403, 404, 419].contains(error.status)) {
      _discardOrderAccount();
    }
  }

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (!ensureOrderAccount()) return Future.value(false);
    return super.perform(() async {
      final result = await action();
      if (mounted) accountScope.check();
      return result;
    }, validate: validate);
  }

  Widget orderContent(List<Widget> children) => content(
    hasOrderAccount
        ? children
        : [
            const ProfileHeading(
              'Order action unavailable',
              '',
              Icons.lock_outline,
            ),
            if (problem == null)
              const Notice(
                'Your buyer account changed or access ended. Reopen this order from your purchases.',
                error: true,
              ),
          ],
  );

  @override
  void dispose() {
    accountScope.invalidate();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _CancelOrderPage extends StatefulWidget {
  const _CancelOrderPage({
    required this.repository,
    required this.page,
    required this.account,
    required this.onSaved,
    this.isRequest = false,
  });
  final ProfileRepository repository;
  final WebPage page;
  final BuyerAccountScope account;
  final ValueChanged<WebPage> onSaved;
  final bool isRequest;
  @override
  State<_CancelOrderPage> createState() => _CancelOrderPageState();
}

class _CancelOrderPageState extends _OrderAccountFormState<_CancelOrderPage> {
  String? _reason;
  final _notes = TextEditingController();

  List<String>? get _cancellationReasons =>
      _completeCancellationReasons(widget.page.props['cancellationReasons']);

  @override
  ProfileRepository get repository => widget.repository;
  @override
  BuyerAccountScope get parentAccount => widget.account;
  @override
  void clearPrivateDraft() {
    _reason = null;
    _notes.clear();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cancellationReasons = _cancellationReasons;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isRequest
                ? 'Request order cancellation'
                : 'Cancel this order?',
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: orderContent([
                ProfileHeading(
                  widget.isRequest ? 'Request cancellation' : 'Cancel order',
                  widget.isRequest
                      ? 'Ask the seller to cancel this order. If the seller does not respond before the deadline, the order cancels automatically.'
                      : 'You can cancel before the seller marks it ready for pickup. Your other orders will continue.',
                  Icons.cancel_outlined,
                ),
                if (cancellationReasons == null)
                  const Notice(
                    'Cancellation reasons could not be confirmed. Refresh this order before trying again.',
                    error: true,
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    for (final reason in cancellationReasons ?? const [])
                      DropdownMenuItem(
                        value: reason,
                        child: Text(reason, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: busy || cancellationReasons == null
                      ? null
                      : (value) => setState(() => _reason = value),
                  validator: (value) => cancellationReasons == null
                      ? 'Cancellation reasons could not be confirmed.'
                      : value == null
                      ? 'Choose a reason.'
                      : null,
                ),
                const SizedBox(height: 20),
                field(
                  'notes',
                  _reason == 'Other reason' ? 'Details' : 'Details (optional)',
                  _notes,
                  required: _reason == 'Other reason',
                  max: 500,
                  lines: 3,
                  check: buyerNotesTextError,
                ),
                SubmitButton(
                  label: widget.isRequest
                      ? 'Submit cancellation request'
                      : 'Cancel order',
                  busy: busy,
                  onPressed: () => perform(() async {
                    final reasons = _cancellationReasons;
                    if (reasons == null ||
                        _reason == null ||
                        !reasons.contains(_reason)) {
                      throw const BackendException(
                        'Cancellation reasons could not be confirmed. Refresh this order before trying again.',
                      );
                    }
                    final id = mapOf(widget.page.props['order'])['id'];
                    final targetUrl = widget.isRequest
                        ? (widget.page.props['cancellationRequestUrl']
                                  as String? ??
                              '/buyer/orders/$id/cancellation-requests')
                        : '/buyer/orders/$id/cancel';
                    final page = await widget.repository.session.submit(
                      targetUrl,
                      {'reason': _reason, 'notes': _notes.text.trim()},
                      referer: '/buyer/orders/$id',
                    );
                    widget.repository.buyer.requireNoErrors(page);
                    accountScope.check(page: page);
                    if (mapOf(page.props['order'])['id'] != id ||
                        (!widget.isRequest &&
                            mapOf(page.props['order'])['status'] !=
                                'cancelled')) {
                      throw const BackendException(
                        'Cancellation was not confirmed. Refresh the order before retrying.',
                      );
                    }
                    if (context.mounted) {
                      widget.onSaved(page);
                      Navigator.pop(context);
                    }
                    return null;
                  }),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({
    required this.repository,
    required this.item,
    required this.orderId,
    required this.account,
    required this.onSaved,
  });
  final ProfileRepository repository;
  final Map<String, dynamic> item;
  final int orderId;
  final BuyerAccountScope account;
  final ValueChanged<WebPage> onSaved;
  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends _OrderAccountFormState<_ReviewPage> {
  late final TextEditingController _comment;
  late final RetryCooldown _reviewCooldown;
  late int _rating;
  final _photos = <UploadPart>[];
  bool get editing => widget.item['review'] != null;
  @override
  ProfileRepository get repository => widget.repository;
  @override
  BuyerAccountScope get parentAccount => widget.account;
  @override
  void clearPrivateDraft() {
    _comment.clear();
    _rating = 0;
    _photos.clear();
  }

  @override
  void initState() {
    super.initState();
    _reviewCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    _comment = TextEditingController(
      text: mapOf(widget.item['review'])['comment']?.toString() ?? '',
    );
    final savedRating = mapOf(widget.item['review'])['rating'];
    _rating = savedRating is int && savedRating >= 1 && savedRating <= 5
        ? savedRating
        : 0;
    if (!hasOrderAccount) _discardOrderAccount();
  }

  @override
  void onFailure(BackendException error) {
    super.onFailure(error);
    if (error.status == 429) {
      _reviewCooldown.start(error.data, retryAt: error.retryAt, notify: false);
    }
  }

  @override
  void dispose() {
    _reviewCooldown.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit purchase review' : 'Rate & Review'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: orderContent([
              ProfileHeading(
                'Review purchased item',
                editing
                    ? 'A review can be edited once within 30 days. Original photos and purchased-item history stay in place.'
                    : 'Share your experience with this exact purchased item and option.',
                Icons.star_outline,
              ),
              OrderItemSummary(
                item: widget.item,
                session: widget.repository.session,
                repository: widget.repository.buyer,
              ),
              Wrap(
                spacing: 4,
                runSpacing: 8,
                children: [
                  for (var rating = 1; rating <= 5; rating++)
                    Semantics(
                      selected: _rating == rating,
                      child: IconButton(
                        tooltip: 'Rate $rating out of 5',
                        onPressed: busy
                            ? null
                            : () => setState(() => _rating = rating),
                        icon: Icon(
                          rating <= _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: BagooTheme.strong,
                          size: 32,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              field(
                'comment',
                'Your review (optional)',
                _comment,
                required: false,
                max: 1000,
                lines: 4,
                check: buyerNotesTextError,
              ),
              if (!editing) ...[
                OutlinedButton.icon(
                  onPressed: busy || _photos.length >= 5
                      ? null
                      : () => perform(() async {
                          final photo = await pickUpload(
                            'photo',
                            imageOnly: true,
                          );
                          if (photo != null && mounted) {
                            setState(() => _photos.add(photo));
                          }
                          return null;
                        }, validate: false),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add review photo'),
                ),
                const Text(
                  'Up to five JPG, PNG or WEBP photos, 5 MB each.',
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
                for (var i = 0; i < _photos.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Image.memory(
                      _photos[i].bytes,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_outlined),
                    ),
                    title: Text(_photos[i].name),
                    trailing: IconButton(
                      tooltip: 'Remove review photo',
                      onPressed: busy
                          ? null
                          : () => setState(() => _photos.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              SubmitButton(
                label: _reviewCooldown.active
                    ? 'Retry review in ${_reviewCooldown.remainingSeconds}s'
                    : editing
                    ? 'Save review edit'
                    : 'Submit review',
                busy: busy,
                onPressed: _reviewCooldown.active
                    ? null
                    : () {
                        if (_reviewCooldown.active) return;
                        perform(() async {
                          if (_rating < 1 || _rating > 5) {
                            throw const BackendException(
                              'Choose a rating from 1 to 5 stars.',
                            );
                          }
                          final page = await widget.repository.session.submit(
                            editing
                                ? '/buyer/reviews/${mapOf(widget.item['review'])['id']}'
                                : '/buyer/reviews',
                            {
                              'rating': _rating,
                              'comment': _comment.text.trim(),
                              if (!editing) 'order_item_id': widget.item['id'],
                            },
                            method: editing ? 'PATCH' : 'POST',
                            referer: '/buyer/orders/${widget.orderId}',
                            files: [
                              for (var i = 0; i < _photos.length; i++)
                                UploadPart(
                                  'images[$i]',
                                  _photos[i].name,
                                  _photos[i].bytes,
                                  _photos[i].mime,
                                ),
                            ],
                          );
                          widget.repository.buyer.requireNoErrors(page);
                          accountScope.check(page: page);
                          if (mapOf(page.props['order'])['id'] !=
                                  widget.orderId ||
                              mapOf(page.props['flash'])['success']
                                  is! String) {
                            throw const BackendException(
                              'The review was not confirmed. Refresh the purchase before trying again.',
                            );
                          }
                          if (context.mounted) {
                            widget.onSaved(page);
                            Navigator.pop(context);
                          }
                          return null;
                        });
                      },
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}
