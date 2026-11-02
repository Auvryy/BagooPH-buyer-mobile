import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/application_text_validation.dart';
import '../../core/pagination_metadata.dart';
import '../../core/retry_cooldown.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/uploads.dart';
import '../../core/request_id.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';
import 'return_codes.dart';

int? _positiveId(dynamic value) => value is int && value > 0 ? value : null;

bool _completeReturnOrder(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return false;
  final order = Map<String, dynamic>.from(value);
  final orderNumber = order['order_number'];
  return _positiveId(order['id']) != null &&
      orderNumber is String &&
      orderNumber.trim().isNotEmpty;
}

Map<String, String>? _returnReasonOptions(Object? value) {
  if (value is! Map || value.isEmpty) return null;
  final options = <String, String>{};
  final labels = <String>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final rawLabel = entry.value;
    if (key is! String ||
        rawLabel is! String ||
        key.trim().isEmpty ||
        key != key.trim() ||
        rawLabel.trim().isEmpty ||
        !labels.add(rawLabel.trim().toLowerCase())) {
      return null;
    }
    options[key] = rawLabel.trim();
  }
  return options.isEmpty ? null : options;
}

List<String> _allowedReturnActions(Object? value, Set<String> allowed) {
  if (value is! List || value.any((action) => action is! String)) {
    return const [];
  }
  final seen = <String>{};
  return value
      .whereType<String>()
      .where((action) => allowed.contains(action) && seen.add(action))
      .toList();
}

bool _completeReturnEvidence(Object? value, int caseId) {
  if (value is! List) return false;
  final ids = <int>{};
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return false;
    final evidence = Map<String, dynamic>.from(row);
    final id = _positiveId(evidence['id']);
    final bytes = evidence['bytes'];
    if (id == null ||
        !ids.add(id) ||
        evidence['url'] != '/buyer-returns/$caseId/evidence/$id' ||
        !const {
          'image/jpeg',
          'image/png',
          'image/webp',
        }.contains(evidence['mime']) ||
        bytes is! int ||
        bytes < 1 ||
        bytes > 5242880 ||
        !const {
          'request',
          'intake',
          'seller-receive',
        }.contains(evidence['purpose'])) {
      return false;
    }
  }
  return true;
}

bool _completeReturnItems(Object? value) {
  if (value is! List) return false;
  final ids = <int>{};
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return false;
    final line = Map<String, dynamic>.from(row);
    final id = _positiveId(line['id']);
    final quantity = line['quantity'];
    final purchase = line['purchase'];
    if (id == null ||
        !ids.add(id) ||
        quantity is! int ||
        quantity < 1 ||
        quantity > 99 ||
        purchase is! Map ||
        purchase.keys.any((key) => key is! String) ||
        purchase['name'] is! String ||
        (purchase['name'] as String).trim().isEmpty ||
        purchase['color'] != null && purchase['color'] is! String ||
        purchase['size'] != null && purchase['size'] is! String) {
      return false;
    }
  }
  return true;
}

bool _completeReturnHubs(Object? value, Object? position) {
  if (value is! List || position is! int || position < 0) return false;
  final ids = <int>{};
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return false;
    final hub = Map<String, dynamic>.from(row);
    final id = _positiveId(hub['id']);
    if (id == null ||
        !ids.add(id) ||
        hub['name'] is! String ||
        (hub['name'] as String).trim().isEmpty ||
        hub['code'] is! String ||
        (hub['code'] as String).trim().isEmpty ||
        hub['address'] is! String ||
        (hub['address'] as String).trim().isEmpty ||
        hub['operating_hours'] != null && hub['operating_hours'] is! String) {
      return false;
    }
  }
  return value.isEmpty ? position == 0 : position < value.length;
}

bool _completeBuyerReturnCustodyActions(Object? value) {
  if (value is! List) return false;
  var hasPrepareLabel = false;
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return false;
    final action = Map<String, dynamic>.from(row);
    if (action['action'] != 'prepare-label' ||
        action['hub_id'] != null ||
        action['label'] is! String ||
        (action['label'] as String).trim().isEmpty ||
        hasPrepareLabel) {
      return false;
    }
    hasPrepareLabel = true;
  }
  return true;
}

bool _completeReturnHistory(Object? value) {
  if (value is! List) return false;
  final references = <String>{};
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return false;
    final event = Map<String, dynamic>.from(row);
    final reference = event['reference'];
    final sourceStatus = event['source_status'];
    if (reference is! String ||
        reference.trim().isEmpty ||
        !references.add(reference) ||
        event['event_type'] is! String ||
        (event['event_type'] as String).trim().isEmpty ||
        event['actor_role'] is! String ||
        (event['actor_role'] as String).trim().isEmpty ||
        event['reason'] is! String ||
        (event['reason'] as String).trim().isEmpty ||
        sourceStatus != null &&
            (sourceStatus is! String || sourceStatus.trim().isEmpty) ||
        event['target_status'] is! String ||
        (event['target_status'] as String).trim().isEmpty ||
        strictDateTime(event['created_at']) == null) {
      return false;
    }
  }
  return true;
}

List<Map<String, dynamic>>? _returnIndexRows(Object? value) {
  if (value is! List) return null;
  final rows = <Map<String, dynamic>>[];
  final ids = <int>{};
  final references = <String>{};
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) return null;
    final item = Map<String, dynamic>.from(row);
    final id = _positiveId(item['id']);
    final reference = item['reference'];
    final orderNumber = item['order_number'];
    final status = item['status'];
    if (id == null ||
        !ids.add(id) ||
        reference is! String ||
        reference.trim().isEmpty ||
        !references.add(reference) ||
        orderNumber is! String ||
        orderNumber.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        strictDateTime(item['created_at']) == null) {
      return null;
    }
    rows.add(item);
  }
  return rows;
}

List<Map<String, dynamic>> _returnMoneyHistory(Object? value) {
  if (value is! List) return const [];
  final events = <Map<String, dynamic>>[];
  final ids = <int>{};
  for (final row in value) {
    if (row is! Map || row.keys.any((key) => key is! String)) {
      return const [];
    }
    final event = Map<String, dynamic>.from(row);
    final type = event['event_type'];
    final amount = event['amount_cents'];
    final id = _positiveId(event['id']);
    if (id == null ||
        !ids.add(id) ||
        type is! String ||
        type.trim().isEmpty ||
        amount is! int ||
        amount < 0 ||
        strictDateTime(event['created_at']) == null ||
        event['reason'] is! String ||
        event['wallet_reference'] != null &&
            event['wallet_reference'] is! String ||
        event['cash_reference'] != null && event['cash_reference'] is! String ||
        event['proof_url'] != null && event['proof_url'] is! String) {
      return const [];
    }
    events.add(event);
  }
  return events;
}

Map<String, int>? _returnAdjustment(Object? value) {
  if (value is! Map) return null;
  const fields = [
    'gross_cents',
    'shop_discount_cents',
    'platform_discount_cents',
    'buyer_cents',
  ];
  final amounts = <String, int>{};
  for (final field in fields) {
    final amount = value[field];
    if (amount is! int || amount < 0) return null;
    amounts[field] = amount;
  }
  return amounts;
}

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({
    super.key,
    required this.repository,
    this.orderId,
    this.caseId,
    this.account,
  });
  final ProfileRepository repository;
  final int? orderId, caseId;
  final BuyerAccountScope? account;
  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends ProfileFormState<ReturnsPage>
    with WidgetsBindingObserver {
  late final BuyerAccountScope _account;
  WebPage? _page;
  bool _writeReady = false;
  int _number = 1;
  int? _createdId;
  final _description = TextEditingController();
  final _photos = <UploadPart>[];
  final _quantities = <int, TextEditingController>{};
  final _selected = <int>{};
  String? _reason;
  Map<String, dynamic>? _submitted;
  late final RetryCooldown _requestCooldown;
  int? get caseId => _createdId ?? widget.caseId;
  Map<String, dynamic> get item => mapOf(_page?.props['returnCase']);
  PaginationMetadata? _casesPagination(
    WebPage page, {
    required int requestedPage,
  }) {
    final raw = page.props['cases'];
    final cases = mapOf(raw);
    final data = cases['data'];
    if (raw is! Map || data is! List) return null;
    final rows = _returnIndexRows(data);
    if (rows == null) return null;
    final basic = parsePaginationMetadata(
      cases,
      rowCount: rows.length,
      requirePageNumbers: true,
    );
    if (basic == null) return null;
    if (basic.currentPage > basic.lastPage) {
      final total = cases['total'];
      if (!isValidBuyerPageRequest(requestedPage) ||
          total is! int ||
          total < 0 ||
          total > maxBuyerPaginationPage * 12 ||
          cases['per_page'] != 12) {
        return null;
      }
      final expectedLast = total == 0 ? 1 : (total + 11) ~/ 12;
      return basic.lastPage == expectedLast &&
              rows.isEmpty &&
              cases['from'] == null &&
              cases['to'] == null
          ? basic
          : null;
    }
    return parseContractPaginationMetadata(
      cases,
      rowCount: rows.length,
      requestedPage: requestedPage,
      pageSize: 12,
    );
  }

  bool get _current =>
      _account.isCurrent &&
      identical(_account.session, widget.repository.session);
  @override
  void initState() {
    super.initState();
    _requestCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    _account =
        widget.account?.fork() ?? BuyerAccountScope(widget.repository.session);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_current) {
      _accessLost();
    }
  }

  @override
  void didUpdateWidget(ReturnsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository.session, widget.repository.session) ||
        !identical(oldWidget.account, widget.account) ||
        oldWidget.orderId != widget.orderId ||
        oldWidget.caseId != widget.caseId) {
      _accessLost();
    }
  }

  @override
  void dispose() {
    _account.invalidate();
    _requestCooldown.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _description.dispose();
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _accept(WebPage page) {
    _account.check(page: page);
    widget.repository.buyer.requireNoErrors(page);
    if (page.user?['role'] != 'buyer' ||
        ![
          'Returns/Index',
          'Returns/Create',
          'Returns/Show',
        ].contains(page.component)) {
      throw const BackendException(
        'These return details are unavailable for your account.',
      );
    }
    if (page.component == 'Returns/Show' &&
        (mapOf(page.props['returnCase'])['id'] is! int ||
            (mapOf(page.props['returnCase'])['id'] as int) < 1 ||
            (caseId != null &&
                mapOf(page.props['returnCase'])['id'] != caseId) ||
            !_completeReturnOrder(mapOf(page.props['returnCase'])['order']) ||
            _positiveId(mapOf(page.props['returnCase'])['version']) == null)) {
      throw const BackendException('This return could not be confirmed.');
    }
    if (page.component == 'Returns/Show') {
      final details = mapOf(page.props['returnCase']);
      if (!_completeReturnItems(details['items'])) {
        throw const BackendException(
          'Returned item details could not be confirmed. Refresh and try again.',
        );
      }
      if (!_completeReturnEvidence(details['evidence'], details['id'] as int)) {
        throw const BackendException(
          'Return evidence could not be confirmed. Refresh and try again.',
        );
      }
      if (!_completeReturnHistory(details['history'])) {
        throw const BackendException(
          'Return history could not be confirmed. Refresh and try again.',
        );
      }
      final custody = mapOf(details['custody']);
      if (custody.isNotEmpty &&
          (!_completeReturnHubs(custody['hubs'], custody['position']) ||
              !_completeBuyerReturnCustodyActions(custody['actions']))) {
        throw const BackendException(
          'Return parcel details could not be confirmed. Refresh and try again.',
        );
      }
    }
    if (page.component == 'Returns/Index') {
      final pagination = _casesPagination(page, requestedPage: _number);
      if (pagination == null || pagination.currentPage > pagination.lastPage) {
        throw const BackendException(
          'Return history pagination could not be confirmed. Refresh and try again.',
        );
      }
    }
    if (page.component == 'Returns/Create') {
      final rows = page.props['items'];
      final ids = <int>{};
      if (rows is! List ||
          rows.any((row) {
            if (row is! Map) return true;
            final purchase = Map<String, dynamic>.from(row);
            final id = _positiveId(purchase['id']);
            final quantity = purchase['quantity'];
            final available = purchase['available_quantity'];
            return id == null ||
                !ids.add(id) ||
                quantity is! int ||
                quantity < 1 ||
                available is! int ||
                available < 0 ||
                available > quantity;
          })) {
        throw const BackendException(
          'These purchased items could not be confirmed. Reload the purchase and try again.',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _page = page;
      _writeReady = true;
      if (page.component == 'Returns/Show') {
        _createdId = item['id'] as int;
      }
      if (page.component == 'Returns/Create') {
        final available = {
          for (final purchase in mapsOf(page.props['items']))
            if ((purchase['available_quantity'] as num) > 0)
              purchase['id'] as int,
        };
        _selected.retainWhere(available.contains);
        if (_returnReasonOptions(page.props['reasons'])?.containsKey(_reason) !=
            true) {
          _reason = null;
        }
      }
    });
    for (final purchase in mapsOf(page.props['items'])) {
      _quantities.putIfAbsent(
        purchase['id'] as int,
        () => TextEditingController(text: '1'),
      );
    }
  }

  void _discardPrivate() {
    _account.invalidate();
    _page = null;
    _writeReady = false;
    _createdId = null;
    _submitted = null;
    _photos.clear();
    _selected.clear();
    _reason = null;
    _description.clear();
    for (final controller in _quantities.values) {
      controller.clear();
    }
    errors = {};
    success = null;
    problem = 'These return details are no longer available for this account. Reopen the return from your purchases.';
  }

  void _accessLost() {
    if (mounted) setState(_discardPrivate);
  }

  @override
  void onFailure(BackendException error) {
    if (error.status == 429 && _submitted != null) {
      _requestCooldown.start(error.data, retryAt: error.retryAt, notify: false);
    }
    if (!_current || [401, 403, 404, 419].contains(error.status)) {
      _discardPrivate();
    }
  }

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (!_current) {
      _accessLost();
      return Future.value(false);
    }
    return super.perform(action, validate: validate);
  }

  Future<void> _load() async => perform(() async {
    _writeReady = false;
    final path = caseId != null
        ? '/buyer-returns/$caseId'
        : widget.orderId != null
        ? '/buyer-returns/orders/${widget.orderId}/create'
        : '/buyer-returns?page=$_number';
    var page = await widget.repository.buyer.document(path);
    _account.check(page: page);
    final expected = caseId != null
        ? 'Returns/Show'
        : widget.orderId != null
        ? 'Returns/Create'
        : 'Returns/Index';
    widget.repository.buyer.requireNoErrors(page);
    if (page.component != expected ||
        (expected == 'Returns/Create' &&
            (mapOf(page.props['order'])['id'] is! int ||
                mapOf(page.props['order'])['id'] != widget.orderId))) {
      throw const BackendException(
        'These return details could not be confirmed.',
      );
    }
    if (expected == 'Returns/Index') {
      var pagination = _casesPagination(page, requestedPage: _number);
      if (pagination == null) {
        throw const BackendException(
          'Return history pagination could not be confirmed. Refresh and try again.',
        );
      }
      if (pagination.currentPage > pagination.lastPage) {
        page = await widget.repository.buyer.document(
          '/buyer-returns?page=${pagination.lastPage}',
        );
        _account.check(page: page);
        widget.repository.buyer.requireNoErrors(page);
        pagination = _casesPagination(page, requestedPage: pagination.lastPage);
        if (page.component != 'Returns/Index' ||
            pagination == null ||
            pagination.currentPage > pagination.lastPage) {
          throw const BackendException(
            'Return history pagination could not be confirmed. Refresh and try again.',
          );
        }
      }
      _number = pagination.currentPage;
    }
    _accept(page);
    return null;
  }, validate: false);
  Future<void> _request() async {
    if (busy || _requestCooldown.active || !_writeReady) return;
    await perform(() async {
      final reasons = _returnReasonOptions(_page!.props['reasons']);
      if (reasons == null) {
        throw const BackendException(
          'Return reasons could not be confirmed. Reload the purchase before requesting a return.',
        );
      }
      if (_reason == null || !reasons.containsKey(_reason)) {
        throw const BackendException('Choose the actual reason.');
      }
      if (_selected.isEmpty || _photos.isEmpty) {
        throw const BackendException(
          'Select at least one purchased item and add one to five photos of the problem.',
        );
      }
      final token =
          _submitted?['request_token'] ?? _page!.props['requestToken'];
      if (token is! String ||
          RegExp(r'^v1\.[a-f0-9-]{36}\.[a-f0-9]{64}$').stringMatch(token) !=
              token) {
        throw const BackendException(
          'The return form could not be confirmed. Reload the current details before requesting a return.',
        );
      }
      _submitted ??= jsonDecode(
        jsonEncode({
          'request_token': token,
          'reason': _reason,
          'description': _description.text.trim(),
          'items': [
            for (final id in _selected)
              {
                'order_item_id': id,
                'quantity': int.parse(_quantities[id]!.text),
              },
          ],
        }),
      ) as Map<String, dynamic>;
      final page = await widget.repository.session.submit(
        '/buyer-returns/orders/${widget.orderId}',
        _submitted!,
        referer: '/buyer-returns/orders/${widget.orderId}/create',
        files: [
          for (var i = 0; i < _photos.length; i++)
            UploadPart(
              'photos[$i]',
              _photos[i].name,
              _photos[i].bytes,
              _photos[i].mime,
            ),
        ],
      );
      _account.check(page: page);
      widget.repository.buyer.requireNoErrors(page);
      final confirmation = mapOf(page.props['flash'])['success'];
      if (page.component != 'Returns/Show' ||
          mapOf(mapOf(page.props['returnCase'])['order'])['id'] !=
              widget.orderId ||
          confirmation is! String ||
          confirmation.trim().isEmpty) {
        throw const BackendException(
          'The return request was not confirmed. Check existing returns before retrying.',
        );
      }
      _accept(page);
      if (mounted) {
        _photos.clear();
        _submitted = null;
      }
      return 'Your return request was saved. The seller can now review it.';
    });
    if (mounted && errors.isNotEmpty) setState(() => _submitted = null);
  }

  void _view(String path, String title) {
    if (!_current) {
      _accessLost();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateDocumentPage(
          repository: widget.repository,
          path: path,
          title: title,
          account: _account,
        ),
      ),
    );
  }

  void _openCase(int id) {
    if (!_current) {
      _accessLost();
      return;
    }
    if (busy || id < 1) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReturnsPage(
          repository: widget.repository,
          caseId: id,
          account: _account,
        ),
      ),
    );
  }

  Future<void> _command(String group, String action, String label) async {
    if (!_current) {
      _accessLost();
      return;
    }
    if (busy || !_writeReady) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReturnCommandPage(
          repository: widget.repository,
          item: item,
          group: group,
          action: action,
          label: label,
          account: _account,
          onAccessLost: _accessLost,
          onSaved: _accept,
        ),
      ),
    );
  }

  List<Widget> _create() {
    final reasons = _returnReasonOptions(_page!.props['reasons']);
    return [
      ProfileHeading(
        'Request a return',
        'Purchase ${mapOf(_page!.props['order'])['order_number']}. Request by ${readableDateTime(_page!.props['requestUntil'])}. Confirming receipt does not end this window. Original shipping stays separate.',
        Icons.assignment_return_outlined,
      ),
      for (final purchase in mapsOf(_page!.props['items'])) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(purchase['name'].toString()),
          subtitle: Text(
            '${[purchase['color'], purchase['size']].whereType<String>().join(' · ')}\nPurchased ${purchase['quantity']} · ${purchase['available_quantity']} available to request',
          ),
          value: _selected.contains(purchase['id']),
          onChanged:
              busy ||
                  _submitted != null ||
                  _positiveId(purchase['id']) == null ||
                  (purchase['available_quantity'] as num) < 1
              ? null
              : (value) => setState(() {
                  final id = _positiveId(purchase['id'])!;
                  value == true ? _selected.add(id) : _selected.remove(id);
                }),
        ),
        if (_selected.contains(purchase['id']))
          field(
            'quantity-${purchase['id']}',
            'Quantity to return',
            _quantities[purchase['id']]!,
            enabled: _submitted == null,
            keyboard: TextInputType.number,
            max: 2,
            check: (value) =>
                RegExp(r'^[1-9][0-9]?$').hasMatch(value) &&
                    int.parse(value) <= (purchase['available_quantity'] as num)
                ? null
                : 'Choose 1 to ${purchase['available_quantity']} units.',
          ),
        const Divider(),
      ],
      const SizedBox(height: 16),
      if (reasons == null)
        const Notice(
          'Return reasons could not be confirmed. Reload the purchase before requesting a return.',
          error: true,
        ),
      DropdownButtonFormField<String>(
        key: ValueKey(Object.hashAll(reasons?.keys ?? const <String>[])),
        initialValue: _reason,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Reason'),
        items: [
          for (final reason
              in reasons?.entries ?? const <MapEntry<String, String>>[])
            DropdownMenuItem(
              value: reason.key,
              child: Text(reason.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: reasons == null || busy || _submitted != null
            ? null
            : (value) => setState(() => _reason = value),
        validator: (value) =>
            value == null || reasons?.containsKey(value) != true
            ? 'Choose the actual reason.'
            : null,
      ),
      const SizedBox(height: 20),
      field(
        'description',
        'What happened?',
        _description,
        min: 10,
        max: 1000,
        lines: 5,
        enabled: _submitted == null,
        check: buyerNotesTextError,
      ),
      OutlinedButton.icon(
        onPressed: busy || _submitted != null || _photos.length >= 5
            ? null
            : () => perform(() async {
                final photo = await pickUpload('photo', imageOnly: true);
                if (photo != null && mounted) {
                  setState(() => _photos.add(photo));
                }
                return null;
              }, validate: false),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add photo of the problem'),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'One to five JPG, PNG or WEBP photos, up to 5 MB each. Photos are private to involved account owners and authorized reviewers.',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
      ),
      for (var index = 0; index < _photos.length; index++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Image.memory(
            _photos[index].bytes,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
          ),
          title: Text(_photos[index].name),
          trailing: IconButton(
            tooltip: 'Remove return photo',
            onPressed: busy || _submitted != null
                ? null
                : () => setState(() => _photos.removeAt(index)),
            icon: const Icon(Icons.close),
          ),
        ),
      if (_submitted != null)
        const Notice(
          'The result is uncertain. Check your existing returns before starting a different request. This retry keeps the exact original details and photos.',
          error: true,
        ),
      const SizedBox(height: 20),
      SubmitButton(
        label: _requestCooldown.active
            ? 'Retry same request in ${_requestCooldown.remainingSeconds}s'
            : _submitted == null
            ? 'Request a return'
            : 'Retry same return request',
        busy: busy,
        onPressed: _writeReady && reasons != null && !_requestCooldown.active
            ? _request
            : null,
      ),
      const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Text(
          'The seller reviews your request first. Approval starts return instructions; repayment follows actual return and payment checks.',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
      ),
    ];
  }

  List<Widget> _show() {
    final custody = mapOf(item['custody']);
    final money = mapOf(item['money']);
    final rawAdjustment = mapOf(money['adjustment']);
    final adjustment = _returnAdjustment(money['adjustment']);
    final moneyHistory = _returnMoneyHistory(money['history']);
    final hasRecordedRepayment = moneyHistory.any(
      (event) => event['event_type'] == 'record-repayment',
    );
    final dropoffDeadline = strictDateTime(item['dropoff_until']);
    final canDropOff =
        custody['can_dropoff'] == true &&
        dropoffDeadline != null &&
        dropoffDeadline.isAfter(DateTime.now());
    final weightGrams = custody['weight_grams'] is num
        ? amount(custody['weight_grams'])
        : null;
    final moneyActions = hasRecordedRepayment
        ? _allowedReturnActions(money['actions'], const {
            'confirm-receipt',
            'report-nonreceipt',
          })
        : const <String>[];
    final returnActions = _allowedReturnActions(item['actions'], const {
      'withdraw',
      'escalate',
      'close-period',
    });
    return [
      ProfileHeading(
        item['reference']?.toString() ?? 'Return request',
        'Purchase ${mapOf(item['order'])['order_number']} · ${item['status'].toString().replaceAll('_', ' ')}',
        Icons.assignment_return_outlined,
      ),
      Text(
        '${item['reason']}\n${item['description']}',
        style: const TextStyle(height: 1.7),
      ),
      const SizedBox(height: 16),
      const ProductHeading('What happens next?'),
      Text(
        returnNextStep(item['status']?.toString()),
        style: const TextStyle(height: 1.7),
      ),
      const SizedBox(height: 16),
      for (final line in mapsOf(item['items']))
        Text(
          '${mapOf(line['purchase'])['name'] ?? 'Purchased item'} × ${line['quantity']}\n${[mapOf(line['purchase'])['color'], mapOf(line['purchase'])['size']].whereType<String>().join(' · ')}',
          style: const TextStyle(height: 1.7),
        ),
      const SizedBox(height: 16),
      for (final evidence in mapsOf(item['evidence']))
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => _view(
                  evidence['url'].toString(),
                  'Private return evidence',
                ),
          icon: const Icon(Icons.image_outlined),
          label: Text(
            'View ${returnEvidencePurpose(evidence['purpose']?.toString())} photo',
          ),
        ),
      for (final deadline in {
        'request_until': 'Request deadline',
        'response_until': 'Seller response deadline',
        'appeal_until': 'Appeal deadline',
        'dropoff_until': 'Drop-off deadline',
      }.entries)
        if (item[deadline.key] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${deadline.value}: ${readableDateTime(item[deadline.key])}',
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
      const Divider(height: 40),
      const ProfileHeading(
        'Return parcel',
        'Follow the recorded return authority and hub handovers. The original delivery waybill does not record this return.',
        Icons.local_shipping_outlined,
      ),
      if (custody.isEmpty)
        const Text('Return parcel details will appear after approval.'),
      if (custody.isNotEmpty) ...[
        Text(
          'Status: ${custody['status']}\nRecorded holder: ${mapOf(custody['custody'])['kind']}\n${custody['current_hub_name'] ?? ''}',
          style: const TextStyle(height: 1.7),
        ),
        if (custody['barcode'] != null) ...[
          ReturnCodes(code: custody['barcode'].toString()),
          const SizedBox(height: 12),
          SelectableText(
            'Return barcode: ${custody['barcode']}',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.7),
          ),
          TextButton.icon(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: custody['barcode'].toString()),
            ),
            icon: const Icon(Icons.copy),
            label: const Text('Copy return code'),
          ),
        ],
        Text(
          weightGrams != null && weightGrams >= 0
              ? 'Recorded weight: ${(weightGrams / 1000).toStringAsFixed(3)} kg'
              : 'Packed weight has not been recorded.',
          style: const TextStyle(height: 1.7),
        ),
        if (custody['manifest_reference'] != null)
          Text(
            'Transport manifest: ${custody['manifest_reference']}',
            style: const TextStyle(height: 1.7),
          ),
        if (mapOf(custody['custody'])['kind'] == 'buyer')
          Text(
            canDropOff
                ? 'Bring the approved items to the original destination Bayan Hub before the drop-off deadline.'
                : 'No current drop-off authority is available. Review the saved decision and deadlines before bringing a parcel.',
            style: const TextStyle(height: 1.7),
          ),
        for (final (index, hub) in mapsOf(custody['hubs']).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${index == custody['position'] ? 'Current route stop · ' : ''}${hub['name']} · ${hub['code']}\n${hub['address']}\n${hub['operating_hours'] ?? 'Contact the hub for operating hours.'}',
              style: const TextStyle(height: 1.7),
            ),
          ),
        for (final action in mapsOf(custody['actions']))
          if (action['action'] == 'prepare-label')
            OutlinedButton(
              onPressed: busy || !_writeReady
                  ? null
                  : () => _command(
                      'custody',
                      'prepare-label',
                      action['label'].toString(),
                    ),
              child: Text(action['label'].toString()),
            ),
      ],
      const Divider(height: 40),
      ProfileHeading(
        money['mode'] == 'wallet' ? 'Wallet return refund' : 'Return repayment',
        'Original merchandise and product discounts determine the amount. Shipping stays separate. Approval and transfer offers do not confirm money received.',
        Icons.receipt_long_outlined,
      ),
      if (rawAdjustment.isEmpty)
        const Text(
          'The original amount can be approved after actual seller receipt and condition review.',
        ),
      if (rawAdjustment.isNotEmpty && adjustment == null)
        const Text(
          'The recorded repayment amount could not be confirmed. Refresh this return before relying on the amount.',
        ),
      if (adjustment != null)
        Text(
          'Original returned merchandise: ${pesos((amount(adjustment['gross_cents']) ?? 0) / 100)}\nProduct discounts: ${pesos(((amount(adjustment['shop_discount_cents']) ?? 0) + (amount(adjustment['platform_discount_cents']) ?? 0)) / 100)}\nBuyer repayment due: ${pesos((amount(adjustment['buyer_cents']) ?? 0) / 100)}',
          style: const TextStyle(height: 1.8, fontWeight: FontWeight.w600),
        ),
      for (final event in moneyHistory)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${event['event_type'].toString().replaceAll('-', ' ')} · ${readableDateTime(event['created_at'])}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.7,
                ),
              ),
              Text(
                '${pesos((amount(event['amount_cents']) ?? 0) / 100)}\n${event['reason']}',
                style: const TextStyle(height: 1.7),
              ),
              if (event['wallet_reference'] != null)
                SelectableText(
                  'Wallet reference: ${event['wallet_reference']}',
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              if (event['cash_reference'] != null)
                SelectableText(
                  'Transfer reference: ${event['cash_reference']}',
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              if (event['proof_url'] is String)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _view(
                          event['proof_url'],
                          'Private repayment receipt',
                        ),
                  child: const Text('View private receipt'),
                ),
            ],
          ),
        ),
      for (final action in moneyActions)
        FilledButton(
          onPressed: busy || !_writeReady
              ? null
              : () => _command(
                  'money',
                  action,
                  action == 'confirm-receipt'
                      ? 'Confirm repayment received'
                      : 'Report repayment not received',
                ),
          child: Text(
            action == 'confirm-receipt'
                ? 'Confirm repayment received'
                : 'Report repayment not received',
          ),
        ),
      const Divider(height: 40),
      const ProfileHeading(
        'Update this return',
        'Available actions follow the current case decision and deadlines.',
        Icons.edit_note,
      ),
      for (final action in returnActions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            onPressed: busy || !_writeReady
                ? null
                : () => _command(
                    'actions',
                    action,
                    {
                      'withdraw': 'Withdraw request',
                      'escalate': 'Ask admin to review',
                      'close-period': 'Close expired period',
                    }[action]!,
                  ),
            child: Text(
              {
                'withdraw': 'Withdraw request',
                'escalate': 'Ask admin to review',
                'close-period': 'Close expired period',
              }[action]!,
            ),
          ),
        ),
      if (returnActions.isEmpty)
        const Text('No return decision actions are currently available.'),
      const Divider(height: 40),
      const ProfileHeading('Recorded history', '', Icons.history),
      for (final event in mapsOf(item['history']))
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            '${event['event_type'].toString().replaceAll('-', ' ')} · ${readableDateTime(event['created_at'])}\n${event['actor_role']?.toString().replaceAll('_', ' ') ?? 'Bagoo'}${event['target_status'] == null ? '' : ' · ${event['target_status'].toString().replaceAll('_', ' ')}'}\n${event['reason'] ?? ''}',
            style: const TextStyle(height: 1.7),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => !_current
      ? Scaffold(
          appBar: AppBar(title: const Text('Returns unavailable')),
          body: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Notice(
                'These return details are no longer available for this account. Reopen the return from your purchases.',
                error: true,
              ),
            ),
          ),
        )
      : PopScope(
          canPop: !busy,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                _page?.component == 'Returns/Create'
                    ? 'Request a return'
                    : 'Returns & Refunds',
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh returns',
                  onPressed: busy || _submitted != null ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: content([
                    if (_page?.component == 'Returns/Create')
                      ..._create()
                    else if (_page?.component == 'Returns/Show')
                      ..._show()
                    else if (_page != null) ...[
                      const ProfileHeading(
                        'Returns and refunds',
                        'If a delivered item has a problem, open its purchase and choose Request a return. Follow decisions, parcel handovers and repayment here.',
                        Icons.assignment_return_outlined,
                      ),
                      if (mapsOf(mapOf(_page!.props['cases'])['data']).isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            'No return requests',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      for (final row in mapsOf(
                        mapOf(_page!.props['cases'])['data'],
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(row['reference'].toString()),
                          subtitle: Text(
                            'Purchase ${row['order_number']}\n${row['status'].toString().replaceAll('_', ' ')}\n${readableDateTime(row['created_at'])}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: busy || _positiveId(row['id']) == null
                              ? null
                              : () => _openCase(_positiveId(row['id'])!),
                        ),
                      ProfilePagination(mapOf(_page!.props['cases']), (number) {
                        _number = number;
                        _load();
                      }, disabled: busy),
                    ],
                    if (problem != null)
                      TextButton(
                        onPressed: busy || _submitted != null ? null : _load,
                        child: const Text('Reload current return details'),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        );
}

class _ReturnCommandPage extends StatefulWidget {
  const _ReturnCommandPage({
    required this.repository,
    required this.item,
    required this.group,
    required this.action,
    required this.label,
    required this.onSaved,
    required this.account,
    required this.onAccessLost,
  });
  final ProfileRepository repository;
  final Map<String, dynamic> item;
  final String group, action, label;
  final ValueChanged<WebPage> onSaved;
  final BuyerAccountScope account;
  final VoidCallback onAccessLost;
  @override
  State<_ReturnCommandPage> createState() => _ReturnCommandPageState();
}

class _ReturnCommandPageState extends ProfileFormState<_ReturnCommandPage> {
  final _reason = TextEditingController();
  final _token = requestId();
  late final RetryCooldown _commandCooldown;
  Map<String, dynamic>? _submitted;
  bool _accessLost = false;
  @override
  void initState() {
    super.initState();
    _commandCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void onFailure(BackendException error) {
    if (!widget.account.isCurrent ||
        [401, 403, 404, 419].contains(error.status)) {
      widget.account.invalidate();
      _accessLost = true;
      _submitted = null;
      _reason.clear();
      widget.onAccessLost();
      return;
    }
    if (error.status == 429 && _submitted != null) {
      _commandCooldown.start(error.data, retryAt: error.retryAt, notify: false);
    }
    if (error.status == 422 || error.fields.isNotEmpty) _submitted = null;
  }

  @override
  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) {
    if (_commandCooldown.active) return Future.value(false);
    if (_accessLost || !widget.account.isCurrent) {
      if (mounted) {
        setState(
          () => onFailure(
            const BackendException('Your buyer account changed.', status: 401),
          ),
        );
      }
      return Future.value(false);
    }
    return super.perform(action, validate: validate);
  }

  @override
  void dispose() {
    _commandCooldown.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _accessLost || !widget.account.isCurrent
      ? Scaffold(
          appBar: AppBar(title: const Text('Return update unavailable')),
          body: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Notice(
                'Your buyer account changed or access ended. Close this update and reopen the return from your purchases.',
                error: true,
              ),
            ),
          ),
        )
      : PopScope(
          canPop: !busy,
          child: Scaffold(
            appBar: AppBar(title: Text(widget.label)),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: content([
                    ProfileHeading(
                      widget.label,
                      '${widget.item['reference']}\n${widget.action == 'confirm-receipt'
                          ? 'Confirm only money you actually received. This records your receipt of the repayment.'
                          : widget.action == 'report-nonreceipt'
                          ? 'Describe the repayment you have not received. The recorded payment remains available for investigation.'
                          : widget.action == 'prepare-label'
                          ? 'Prepare the separate return label using the current approved authority.'
                          : 'Explain the actual reason for this return update.'}',
                      Icons.assignment_return_outlined,
                    ),
                    field(
                      'reason',
                      'Reason or receipt details',
                      _reason,
                      min: 10,
                      max: 1000,
                      lines: 4,
                      enabled: _submitted == null,
                      check: buyerNotesTextError,
                    ),
                    if (_submitted != null)
                      const Notice(
                        'The last response is uncertain. Retry this exact update or close and refresh the return history.',
                        error: true,
                      ),
                    SubmitButton(
                      label: _commandCooldown.active
                          ? 'Retry same update in ${_commandCooldown.remainingSeconds}s'
                          : _submitted == null
                          ? widget.label
                          : 'Retry same update',
                      busy: busy,
                      onPressed: _commandCooldown.active
                          ? null
                          : () => perform(() async {
                              final payment =
                                  _returnMoneyHistory(
                                        mapOf(widget.item['money'])['history'],
                                      )
                                      .where(
                                        (event) =>
                                            event['event_type'] ==
                                            'record-repayment',
                                      )
                                      .lastOrNull;
                              final version = widget.item['version'];
                              final source = payment?['id'];
                              if (version is! int ||
                                  version < 1 ||
                                  widget.group == 'money' &&
                                      (source is! int || source < 1)) {
                                throw const BackendException(
                                  'The current return version or repayment could not be confirmed. Close this update and reload its saved history.',
                                );
                              }
                              _submitted ??= {
                                'action': widget.action,
                                'expected_version': version,
                                'request_token': _token,
                                'reason': _reason.text.trim(),
                                if (widget.group == 'money')
                                  'source_event_id': source,
                              };
                              final id = widget.item['id'];
                              final page = await widget.repository.session
                                  .submit(
                                    '/buyer-returns/$id/${widget.group}',
                                    _submitted!,
                                    referer: '/buyer-returns/$id',
                                  );
                              widget.account.check(page: page);
                              widget.repository.buyer.requireNoErrors(page);
                              final confirmation = mapOf(
                                page.props['flash'],
                              )['success'];
                              if (page.component != 'Returns/Show' ||
                                  mapOf(page.props['returnCase'])['id'] != id ||
                                  confirmation is! String ||
                                  confirmation.trim().isEmpty) {
                                throw const BackendException(
                                  'This return update was not confirmed. Refresh its history before retrying.',
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
