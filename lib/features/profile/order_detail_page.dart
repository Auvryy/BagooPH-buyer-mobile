import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../../core/foreground_refresh.dart';
import '../../core/widgets.dart';
import '../../core/uploads.dart';
import '../home/product_card.dart';
import '../products/product_widgets.dart';
import 'profile_widgets.dart';
import 'profile_repository.dart';
import 'purchases_section.dart';
import 'returns_page.dart';
import 'order_journey.dart';
import '../checkout/commerce_details.dart';
import '../engagement/engagement_repository.dart';

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
  late ForegroundRead _updates;
  late int _identityEpoch;
  String? _updateError;
  bool _refreshing = true, _accessLost = false, _manualRefresh = false;
  Map<String, dynamic> get order => mapOf(_page?.props['order']);
  Map<String, dynamic> get claim => mapOf(_page?.props['pickupClaim']);
  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    _identityEpoch = widget.repository.session.identityEpoch;
    _updates = ForegroundRead(read: _read);
  }

  @override
  void didUpdateWidget(covariant OrderDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.orderId != widget.orderId) {
      _updates.dispose();
      _claimTimer?.cancel();
      _page = null;
      _code = _updateError = problem = success = null;
      errors = {};
      _accessLost = _manualRefresh = false;
      _refreshing = true;
      _configure();
    }
  }

  @override
  void dispose() {
    _updates.dispose();
    _claimTimer?.cancel();
    _code = null;
    super.dispose();
  }

  bool get readyForPickup {
    final expiry = DateTime.tryParse(claim['expires_at']?.toString() ?? '');
    final locked = DateTime.tryParse(claim['locked_until']?.toString() ?? '');
    return claim['status'] == 'ready' &&
        expiry != null &&
        expiry.isAfter(DateTime.now()) &&
        (claim['locked_until'] == null ||
            locked != null && !locked.isAfter(DateTime.now()));
  }

  void _accept(WebPage page) {
    widget.repository.buyer.requireNoErrors(page);
    if (_identityEpoch != widget.repository.session.identityEpoch ||
        page.component != 'Buyer/OrderDetail' ||
        mapOf(page.props['order'])['id'] != widget.orderId ||
        page.user?['id'] is! num ||
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
            .map((v) => DateTime.tryParse(v?.toString() ?? ''))
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
    if (_accessLost ||
        _identityEpoch != widget.repository.session.identityEpoch) {
      setState(() {
        _clearPrivate();
        problem = 'Your account changed. Reopen this order after signing in.';
      });
      return Future.value(false);
    }
    _updates.setActive(false);
    return super.perform(action, validate: validate);
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
    if (!await confirmAction(
      context,
      'Confirm receipt?',
      'Confirm that you received order #${order['order_number']} and checked its items. This records your receipt and completes the purchase.',
      'Confirm Received',
    )) {
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
  }

  Future<void> _pickup() async {
    if (!readyForPickup || claim['code_issued_at'] != null || _code != null) {
      return;
    }
    if (!await confirmAction(
      context,
      'Show your private pickup code?',
      'This code is shown once. Keep it private and save it when it appears; it cannot be revealed again.',
      'Show my code once',
    )) {
      return;
    }
    await perform(() async {
      final data = await widget.repository.json(
        '/buyer/orders/${widget.orderId}/pickup-code',
        {},
      );
      if (data['code'] is! String || data['code'].toString().isEmpty) {
        throw const BackendException(
          'The pickup code was not returned. Refresh tracking before trying again.',
        );
      }
      if (mounted &&
          readyForPickup &&
          _identityEpoch == widget.repository.session.identityEpoch) {
        setState(() => _code = data['code']);
      }
      return 'Keep your code private. Present it with your valid photo ID at the assigned hub.';
    }, validate: false);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = mapOf(order['tracking']);
    final userCan = _page?.props['canUsePortal'] == true;
    final canAct =
        !busy && !_accessLost && problem == null && _updateError == null;
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
                    if (_page != null) ...[
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
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_page!.props['canConfirmReceipt'] == true)
                                  FilledButton(
                                    onPressed: canAct ? _confirm : null,
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
                                                onSaved: _accept,
                                              ),
                                            ),
                                          )
                                        : null,
                                    child: const Text('Cancel order'),
                                  ),
                                if (mapOf(
                                      _page!.props['returnAvailability'],
                                    )['can_request'] ==
                                    true)
                                  OutlinedButton(
                                    onPressed: canAct
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => ReturnsPage(
                                                repository: widget.repository,
                                                orderId: widget.orderId,
                                              ),
                                            ),
                                          )
                                        : null,
                                    child: const Text('Request return/refund'),
                                  ),
                                if (order['wallet_payment'] is Map)
                                  TextButton(
                                    onPressed: canAct
                                        ? () => perform(() async {
                                            await openWalletPayment(
                                              context,
                                              widget.repository,
                                              (mapOf(
                                                        order['wallet_payment'],
                                                      )['id']
                                                      as num)
                                                  .toInt(),
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
                                  onPressed: canAct ? _pickup : null,
                                  child: const Text('Show my code once'),
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
                            for (final item in mapsOf(order['items'])) ...[
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
                      if (mapsOf(_page!.props['buyerReturns']).isNotEmpty)
                        ProfilePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProfileHeading(
                                'Returns & Refunds',
                                '',
                                Icons.assignment_return_outlined,
                              ),
                              for (final item in mapsOf(
                                _page!.props['buyerReturns'],
                              ))
                                ListTile(
                                  title: Text(item['reference'].toString()),
                                  subtitle: Text(item['status'].toString()),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ReturnsPage(
                                        repository: widget.repository,
                                        caseId: (item['id'] as num).toInt(),
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
                          notices: mapsOf(_page!.props['orderNotices']),
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
}

class _CancelOrderPage extends StatefulWidget {
  const _CancelOrderPage({
    required this.repository,
    required this.page,
    required this.onSaved,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onSaved;
  @override
  State<_CancelOrderPage> createState() => _CancelOrderPageState();
}

class _CancelOrderPageState extends ProfileFormState<_CancelOrderPage> {
  String? _reason;
  final _notes = TextEditingController();
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Cancel this order?')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: content([
              const ProfileHeading(
                'Cancel order',
                'You can cancel before the seller marks it ready for pickup. Your other orders will continue.',
                Icons.cancel_outlined,
              ),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [
                  for (final reason
                      in widget.page.props['cancellationReasons'] as List? ??
                          [])
                    DropdownMenuItem(
                      value: reason.toString(),
                      child: Text(
                        reason.toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => _reason = value),
                validator: (value) => value == null ? 'Choose a reason.' : null,
              ),
              const SizedBox(height: 20),
              field(
                'notes',
                _reason == 'Other reason' ? 'Details' : 'Details (optional)',
                _notes,
                required: _reason == 'Other reason',
                max: 500,
                lines: 3,
              ),
              SubmitButton(
                label: 'Cancel order',
                busy: busy,
                onPressed: () => perform(() async {
                  final id = mapOf(widget.page.props['order'])['id'];
                  final page = await widget.repository.session.submit(
                    '/buyer/orders/$id/cancel',
                    {'reason': _reason, 'notes': _notes.text.trim()},
                    referer: '/buyer/orders/$id',
                  );
                  widget.repository.buyer.requireNoErrors(page);
                  if (mapOf(page.props['order'])['id'] != id ||
                      mapOf(page.props['order'])['status'] != 'cancelled') {
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

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({
    required this.repository,
    required this.item,
    required this.orderId,
    required this.onSaved,
  });
  final ProfileRepository repository;
  final Map<String, dynamic> item;
  final int orderId;
  final ValueChanged<WebPage> onSaved;
  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ProfileFormState<_ReviewPage> {
  late final TextEditingController _comment;
  late int _rating;
  final _photos = <UploadPart>[];
  bool get editing => widget.item['review'] != null;
  @override
  void initState() {
    super.initState();
    _comment = TextEditingController(
      text: mapOf(widget.item['review'])['comment']?.toString() ?? '',
    );
    _rating = (mapOf(widget.item['review'])['rating'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {
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
            child: content([
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
                label: editing ? 'Save review edit' : 'Submit review',
                busy: busy,
                onPressed: () => perform(() async {
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
                  if (mapOf(page.props['order'])['id'] != widget.orderId ||
                      mapOf(page.props['flash'])['success'] is! String) {
                    throw const BackendException(
                      'The review was not confirmed. Refresh the purchase before trying again.',
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
