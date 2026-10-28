import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/web_session.dart';
import '../../core/uploads.dart';
import '../../core/request_id.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';
import 'return_codes.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({
    super.key,
    required this.repository,
    this.orderId,
    this.caseId,
  });
  final ProfileRepository repository;
  final int? orderId, caseId;
  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends ProfileFormState<ReturnsPage> {
  WebPage? _page;
  int _number = 1;
  int? _createdId;
  final _description = TextEditingController();
  final _photos = <UploadPart>[];
  final _quantities = <int, TextEditingController>{};
  final _selected = <int>{};
  String? _reason;
  Map<String, dynamic>? _submitted;
  int? get caseId => _createdId ?? widget.caseId;
  Map<String, dynamic> get item => mapOf(_page?.props['returnCase']);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _accept(WebPage page) {
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
        (mapOf(page.props['returnCase'])['id'] is! num ||
            (caseId != null &&
                mapOf(page.props['returnCase'])['id'] != caseId))) {
      throw const BackendException('This return could not be confirmed.');
    }
    if (!mounted) return;
    setState(() {
      _page = page;
      if (page.component == 'Returns/Show') {
        _createdId = (item['id'] as num).toInt();
      }
    });
    for (final purchase in mapsOf(page.props['items'])) {
      _quantities.putIfAbsent(
        (purchase['id'] as num).toInt(),
        () => TextEditingController(text: '1'),
      );
    }
  }

  Future<void> _load() async => perform(() async {
    final path = caseId != null
        ? '/buyer-returns/$caseId'
        : widget.orderId != null
        ? '/buyer-returns/orders/${widget.orderId}/create'
        : '/buyer-returns?page=$_number';
    final page = await widget.repository.buyer.document(path);
    final expected = caseId != null
        ? 'Returns/Show'
        : widget.orderId != null
        ? 'Returns/Create'
        : 'Returns/Index';
    widget.repository.buyer.requireNoErrors(page);
    if (page.component != expected ||
        (expected == 'Returns/Create' &&
            mapOf(page.props['order'])['id'] != widget.orderId)) {
      throw const BackendException(
        'These return details could not be confirmed.',
      );
    }
    _accept(page);
    return null;
  }, validate: false);
  Future<void> _request() async {
    await perform(() async {
      if (_selected.isEmpty || _photos.isEmpty) {
        throw const BackendException(
          'Select at least one purchased item and add one to five photos of the problem.',
        );
      }
      _submitted ??= jsonDecode(
        jsonEncode({
          'request_token': _page!.props['requestToken'],
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
      widget.repository.buyer.requireNoErrors(page);
      if (page.component != 'Returns/Show' ||
          mapOf(mapOf(page.props['returnCase'])['order'])['id'] !=
              widget.orderId ||
          mapOf(page.props['flash'])['success'] is! String) {
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

  void _view(String path, String title) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrivateDocumentPage(
        repository: widget.repository,
        path: path,
        title: title,
      ),
    ),
  );
  Future<void> _command(String group, String action, String label) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReturnCommandPage(
          repository: widget.repository,
          item: item,
          group: group,
          action: action,
          label: label,
          onSaved: _accept,
        ),
      ),
    );
  }

  List<Widget> _create() => [
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
                (purchase['available_quantity'] as num) < 1
            ? null
            : (value) => setState(() {
                value == true
                    ? _selected.add((purchase['id'] as num).toInt())
                    : _selected.remove(purchase['id']);
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
    DropdownButtonFormField<String>(
      initialValue: _reason,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Reason'),
      items: [
        for (final reason in mapOf(_page!.props['reasons']).entries)
          DropdownMenuItem(
            value: reason.key,
            child: Text(
              reason.value.toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: busy || _submitted != null
          ? null
          : (value) => setState(() => _reason = value),
      validator: (value) => value == null ? 'Choose the actual reason.' : null,
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
    ),
    OutlinedButton.icon(
      onPressed: busy || _submitted != null || _photos.length >= 5
          ? null
          : () => perform(() async {
              final photo = await pickUpload('photo', imageOnly: true);
              if (photo != null && mounted) setState(() => _photos.add(photo));
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
      label: _submitted == null
          ? 'Request a return'
          : 'Retry same return request',
      busy: busy,
      onPressed: _request,
    ),
    const Padding(
      padding: EdgeInsets.only(top: 16),
      child: Text(
        'The seller reviews your request first. Approval starts return instructions; repayment follows actual return and payment checks.',
        style: TextStyle(fontSize: 12, height: 1.7),
      ),
    ),
  ];
  List<Widget> _show() {
    final custody = mapOf(item['custody']);
    final money = mapOf(item['money']);
    final adjustment = mapOf(money['adjustment']);
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
          custody['weight_grams'] is num
              ? 'Recorded weight: ${((custody['weight_grams'] as num) / 1000).toStringAsFixed(3)} kg'
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
            custody['can_dropoff'] == true
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
              onPressed: busy
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
      if (adjustment.isEmpty)
        const Text(
          'The original amount can be approved after actual seller receipt and condition review.',
        ),
      if (adjustment.isNotEmpty)
        Text(
          'Original returned merchandise: ${pesos((amount(adjustment['gross_cents']) ?? 0) / 100)}\nProduct discounts: ${pesos(((amount(adjustment['shop_discount_cents']) ?? 0) + (amount(adjustment['platform_discount_cents']) ?? 0)) / 100)}\nBuyer repayment due: ${pesos((amount(adjustment['buyer_cents']) ?? 0) / 100)}',
          style: const TextStyle(height: 1.8, fontWeight: FontWeight.w600),
        ),
      for (final event in mapsOf(money['history']))
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
      for (final action in (money['actions'] as List? ?? []))
        if (['confirm-receipt', 'report-nonreceipt'].contains(action))
          FilledButton(
            onPressed: busy
                ? null
                : () => _command(
                    'money',
                    action.toString(),
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
      for (final action in (item['actions'] as List? ?? []))
        if (['withdraw', 'escalate', 'close-period'].contains(action))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => _command(
                      'actions',
                      action.toString(),
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
      if ((item['actions'] as List? ?? []).isEmpty)
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
  Widget build(BuildContext context) => PopScope(
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
                for (final row in mapsOf(mapOf(_page!.props['cases'])['data']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['reference'].toString()),
                    subtitle: Text(
                      'Purchase ${row['order_number']}\n${row['status'].toString().replaceAll('_', ' ')}\n${readableDateTime(row['created_at'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReturnsPage(
                                repository: widget.repository,
                                caseId: (row['id'] as num).toInt(),
                              ),
                            ),
                          ),
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
  });
  final ProfileRepository repository;
  final Map<String, dynamic> item;
  final String group, action, label;
  final ValueChanged<WebPage> onSaved;
  @override
  State<_ReturnCommandPage> createState() => _ReturnCommandPageState();
}

class _ReturnCommandPageState extends ProfileFormState<_ReturnCommandPage> {
  final _reason = TextEditingController();
  final _token = requestId();
  Map<String, dynamic>? _submitted;
  @override
  void onFailure(BackendException error) {
    if (error.status == 422 || error.fields.isNotEmpty) _submitted = null;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
              ),
              if (_submitted != null)
                const Notice(
                  'The last response is uncertain. Retry this exact update or close and refresh the return history.',
                  error: true,
                ),
              SubmitButton(
                label: _submitted == null ? widget.label : 'Retry same update',
                busy: busy,
                onPressed: () => perform(() async {
                  final payment = mapsOf(mapOf(widget.item['money'])['history'])
                      .where(
                        (event) => event['event_type'] == 'record-repayment',
                      )
                      .lastOrNull;
                  _submitted ??= {
                    'action': widget.action,
                    'expected_version': widget.item['version'],
                    'request_token': _token,
                    'reason': _reason.text.trim(),
                    if (widget.group == 'money')
                      'source_event_id': payment?['id'],
                  };
                  final id = widget.item['id'];
                  final page = await widget.repository.session.submit(
                    '/buyer-returns/$id/${widget.group}',
                    _submitted!,
                    referer: '/buyer-returns/$id',
                  );
                  widget.repository.buyer.requireNoErrors(page);
                  if (page.component != 'Returns/Show' ||
                      mapOf(page.props['returnCase'])['id'] != id ||
                      mapOf(page.props['flash'])['success'] is! String) {
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
