import 'dart:io';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/products/product_widgets.dart';
import 'package:bagoo_buyer_mobile/features/checkout/voucher_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../test/support/no_network.dart';
import '../test/support/voucher_fixtures.dart';
import 'preview/buyer_device_preview.dart';

void main() {
  if (!kDebugMode || !Platform.isLinux) {
    throw UnsupportedError('The isolated voucher review requires debug Linux.');
  }
  HttpOverrides.global = NoNetworkHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _VoucherReview());
}

class _VoucherReview extends StatefulWidget {
  const _VoucherReview();
  @override
  State<_VoucherReview> createState() => _VoucherReviewState();
}

class _VoucherReviewState extends State<_VoucherReview> {
  static const modes = {
    'ready': 'Successful response',
    'offline': 'Connection failure',
    'denied': 'Access denied',
    'invalid': 'Invalid bookmark reply',
  };
  VoucherReviewSession? _session;
  late VoucherPickerReviewRepository _picker;
  Map<String, dynamic>? _selected;
  final _bookmarks = <int, int>{};
  int _nextSaved = 21;
  Map<String, dynamic> _offer = reviewOffer();
  String _mode = 'ready';
  int _revision = 0, _reloads = 0;
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _session?.close();
    final session = _session = VoucherReviewSession();
    _picker = VoucherPickerReviewRepository(session);
    _selected = null;
    _bookmarks.clear();
    _nextSaved = 21;
    _offer = reviewOffer();
    _allowed = true;
    _reloads = 0;
    _revision++;
    Future<void> response(String mode) async {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(session, _session)) setState(() {});
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || !identical(session, _session)) {
        throw const BackendException(
          'This synthetic voucher was reset.',
          status: 401,
        );
      }
      if (mode == 'offline' || mode == 'denied') {
        throw BackendException(
          mode == 'offline'
              ? 'The synthetic request was not confirmed. Retry explicitly for the same selection.'
              : 'Access to these synthetic vouchers ended.',
          status: mode == 'offline' ? 503 : 403,
        );
      }
    }

    session.reply = (path, method) async {
      final mode = _mode;
      await response(mode);
      if (mode == 'invalid') return {'saved_id': -1};
      final id = int.parse(Uri.parse(path).pathSegments.last);
      if (method == 'DELETE') {
        _bookmarks.removeWhere((_, saved) => saved == id);
      } else {
        _bookmarks.putIfAbsent(id, () => _nextSaved++);
      }
      return {'saved_id': method == 'DELETE' ? null : _bookmarks[id]};
    };
    _picker.choices = (values) async {
      final mode = _mode;
      await response(mode);
      if (mode == 'invalid') {
        return {
          'offers': {'current_page': 'unknown', 'last_page': 3, 'data': []},
        };
      }
      final result = reviewChoices(values['voucher_page'] as int);
      for (final row in (result['offers'] as Map)['data'] as List) {
        row['saved_id'] = _bookmarks[row['revision_id']];
      }
      return result;
    };
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Banner(
      message: 'ISOLATED QA',
      location: BannerLocation.topEnd,
      child: BuyerDevicePreview(
        extraControls: [
          const Divider(height: 36),
          const Text(
            'Buyer voucher review',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Next response'),
            items: [
              for (final entry in modes.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save permitted'),
            value: _allowed,
            onChanged: (value) => setState(() => _allowed = value),
          ),
          OutlinedButton(
            onPressed: () => setState(_reset),
            child: const Text('Reset test voucher'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _session!.clear();
              _selected = null;
            }),
            child: const Text('Change test account'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(
              () => _offer = reviewOffer(
                revision: (_offer['revision_id'] as int) + 1,
              ),
            ),
            child: const Text('Change displayed offer'),
          ),
          const SizedBox(height: 12),
          Text('Mutation attempts: ${_session!.writes.length}'),
          Text('Confirmed refreshes: $_reloads'),
          Text('Choice requests: ${_picker.choiceRequests.length}'),
          const SizedBox(height: 12),
          const Text(
            'Synthetic offers and replies. Outbound requests are blocked. No real bookmark, discount or payment is changed.',
          ),
        ],
        builder: (context) => MaterialApp(
          key: ValueKey(_revision),
          theme: Theme.of(context),
          debugShowCheckedModeBanner: false,
          scrollBehavior: ScrollConfiguration.of(context),
          home: Builder(
            builder: (pageContext) => Scaffold(
              appBar: AppBar(title: const Text('Vouchers & Promos')),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OfferTile(
                        key: const ValueKey('review-voucher'),
                        offer: _offer,
                        repository: voucherRepository(_session!),
                        canSave: _allowed,
                        onSaved: () async {
                          if (mounted) setState(() => _reloads++);
                        },
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final session = _session!,
                              epoch = _session!.identityEpoch;
                          final selected = await Navigator.of(pageContext)
                              .push<Map<String, dynamic>>(
                                MaterialPageRoute(
                                  builder: (_) => VoucherPickerPage(
                                    repository: _picker,
                                    values: const {
                                      'item_ids': [1],
                                      'delivery_type': 'doorstep',
                                    },
                                    title: 'Synthetic voucher choices',
                                    selectedRevision: 11,
                                  ),
                                ),
                              );
                          if (mounted &&
                              identical(session, _session) &&
                              epoch == session.identityEpoch) {
                            setState(() {
                              _selected = selected;
                              _offer = {
                                ..._offer,
                                'saved_id': _bookmarks[_offer['revision_id']],
                              };
                            });
                          }
                        },
                        child: const Text('Open voucher picker'),
                      ),
                      if (_selected != null)
                        Text(
                          _selected!['remove'] == true
                              ? 'Current voucher removed from this synthetic selection.'
                              : 'Selected revision: ${_selected!['revision_id']}',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
