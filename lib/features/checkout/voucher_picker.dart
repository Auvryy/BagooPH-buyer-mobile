import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/pagination_metadata.dart';
import '../../core/retry_cooldown.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_widgets.dart';
import '../products/product_model.dart' show pesos;

class VoucherPickerPage extends StatefulWidget {
  const VoucherPickerPage({
    super.key,
    required this.repository,
    required this.values,
    required this.title,
    this.shopId,
    this.selectedRevision,
    this.account,
  });
  final BuyerRepository repository;
  final Map<String, dynamic> values;
  final String title;
  final int? shopId, selectedRevision;
  final BuyerAccountScope? account;
  @override
  State<VoucherPickerPage> createState() => _VoucherPickerPageState();
}

class _VoucherPickerPageState extends State<VoucherPickerPage>
    with WidgetsBindingObserver {
  late final BuyerAccountScope _account;
  late BuyerAccountScope _offersAccount;
  late final Map<String, dynamic> _values;
  late final String _input;
  late final RetryCooldown _choicesCooldown;
  Map<String, dynamic> _page = {};
  bool _loading = false, _decided = false;
  String? _error;
  int _number = 1, _generation = 0;

  void _expire({bool rebuild = true, bool propagate = false}) {
    if (!mounted) return;
    if (propagate) widget.account?.invalidate();
    void clear() {
      _account.invalidate();
      _offersAccount.invalidate();
      _generation++;
      _page = {};
      _values.clear();
      _loading = false;
      _choicesCooldown.clear(notify: false);
      _error = 'Your buyer account changed or voucher access ended. Close this picker and reopen it from checkout.';
    }

    if (rebuild) {
      setState(clear);
    } else {
      clear();
    }
  }

  bool _ensure({bool rebuild = true}) {
    if (!mounted) return false;
    if (_account.isCurrent &&
        identical(_account.session, widget.repository.session)) {
      return true;
    }
    if (_account.isCurrent ||
        _values.isNotEmpty ||
        _page.isNotEmpty ||
        _error == null) {
      _expire(rebuild: rebuild);
    }
    return false;
  }

  Map<String, dynamic> _checkedPage(
    Map<String, dynamic> result,
    int requested,
  ) {
    final rawPage = result['offers'];
    if (rawPage is! Map || rawPage.keys.any((key) => key is! String)) {
      throw const BackendException(
        'These voucher choices could not be confirmed. Try again.',
      );
    }
    final page = Map<String, dynamic>.from(rawPage);
    final current = page['current_page'], last = page['last_page'];
    final rows = page['data'];
    if (current is! int ||
        current != requested ||
        current < 1 ||
        current > 100000 ||
        last is! int ||
        last < 1 ||
        last > 100000 ||
        page['per_page'] != 12 ||
        rows is! List ||
        rows.length > 12 ||
        rows.any(
          (row) => row is! Map || row.keys.any((key) => key is! String),
        )) {
      throw const BackendException(
        'These voucher choices could not be confirmed. Try again.',
      );
    }
    final offers = requireRowsWithIds(
      rows,
      idKey: 'revision_id',
      error: 'These voucher choices could not be confirmed. Try again.',
    );
    final pagination = parsePaginationMetadata(
      page,
      rowCount: offers.length,
      requirePageNumbers: true,
    );
    final expectedLastPage = pagination == null || pagination.total == 0
        ? 1
        : (pagination.total + 11) ~/ 12;
    final outOfRange = current > last;
    final expectedRows =
        pagination == null || outOfRange || pagination.total == 0
        ? 0
        : current < last
        ? 12
        : pagination.total - (last - 1) * 12;
    final validRange =
        pagination != null &&
        pagination.lastPage == expectedLastPage &&
        offers.length == expectedRows &&
        (!outOfRange || offers.isEmpty) &&
        (outOfRange || pagination.total == 0 || offers.isNotEmpty) &&
        (offers.isEmpty ||
            pagination.from == (current - 1) * 12 + 1 &&
                pagination.to == pagination.from! + offers.length - 1);
    if (!validRange) {
      throw const BackendException(
        'These voucher choices could not be confirmed. Try again.',
      );
    }
    return {...page, 'data': offers};
  }

  Future<void> _load({int? target}) async {
    if (!_ensure() || _loading || _decided || _choicesCooldown.active) return;
    final generation = ++_generation;
    _offersAccount.invalidate();
    var requested = target ?? _number;
    setState(() {
      _number = requested;
      _loading = true;
      _error = null;
      _page = {};
    });
    try {
      Map<String, dynamic>? page;
      for (var attempt = 0; attempt < 2; attempt++) {
        final data = await widget.repository.voucherChoices({
          ...jsonDecode(jsonEncode(_values)) as Map<String, dynamic>,
          'shop_id': widget.shopId,
          'voucher_page': requested,
        });
        if (!_ensure() || generation != _generation || _decided) return;
        page = _checkedPage(data, requested);
        if (requested <= (page['last_page'] as int)) break;
        if (attempt == 1) {
          throw const BackendException(
            'Voucher pages changed again. Try again.',
          );
        }
        requested = page['last_page'] as int;
      }
      if (!_ensure() || generation != _generation || _decided) return;
      setState(() {
        _number = requested;
        _page = page!;
        _offersAccount = _account.fork();
      });
    } on BackendException catch (error) {
      if (!_ensure() || generation != _generation) return;
      if ([401, 403, 404, 419].contains(error.status)) {
        _expire(propagate: true);
        return;
      }
      if (error.status == 429) {
        _choicesCooldown.start(
          error.data,
          retryAt: error.retryAt,
          notify: false,
        );
      }
      setState(() => _error = error.message);
    } finally {
      if (mounted && _account.isCurrent && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _changePage(int delta, int from, int generation) {
    if (!_ensure() ||
        _loading ||
        _choicesCooldown.active ||
        _decided ||
        generation != _generation ||
        from != _number) {
      return;
    }
    final last = _page['last_page'] as int? ?? 1;
    final target = from + delta;
    if (target < 1 || target > last || target > 100000) return;
    _load(target: target);
  }

  bool get _canDecide =>
      mounted && !_decided && ModalRoute.of(context)?.isCurrent == true;
  void _close() {
    if (!_canDecide) return;
    _decided = true;
    Navigator.pop(context);
  }

  void _choose(Map<String, dynamic> offer, int generation) {
    if (!_canDecide || !_ensure() || _loading || generation != _generation) {
      return;
    }
    final revision = offer['revision_id'];
    final correctSlot = widget.shopId == null
        ? offer['issuer'] == 'platform' && offer['shop_id'] == null
        : offer['issuer'] == 'shop' && offer['shop_id'] == widget.shopId;
    if (positiveInt32ResourceId(revision) == null ||
        offer['eligible'] != true ||
        !correctSlot) {
      return;
    }
    _decided = true;
    Navigator.pop(context, Map<String, dynamic>.of(offer));
  }

  void _remove(int generation) {
    if (!_canDecide ||
        !_ensure() ||
        _loading ||
        generation != _generation ||
        widget.selectedRevision == null) {
      return;
    }
    _decided = true;
    Navigator.pop(context, <String, dynamic>{'remove': true});
  }

  @override
  void initState() {
    super.initState();
    _choicesCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _account = (widget.account ?? BuyerAccountScope(widget.repository.session))
        .fork();
    _offersAccount = _account.fork();
    _input = jsonEncode(widget.values);
    _values = jsonDecode(_input) as Map<String, dynamic>;
    if (_account.isCurrent) {
      _load();
    } else {
      _expire(rebuild: false);
    }
  }

  @override
  void didUpdateWidget(VoucherPickerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.account, widget.account) ||
        !identical(_account.session, widget.repository.session) ||
        oldWidget.shopId != widget.shopId ||
        !identical(oldWidget.values, widget.values) &&
            jsonEncode(widget.values) != _input) {
      _expire(rebuild: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ensure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _account.invalidate();
    _offersAccount.invalidate();
    _choicesCooldown.dispose();
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _ensure(rebuild: false);
    final generation = _generation;
    final number = _number;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _decided = true;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: !current
            ? SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Notice(_error!, error: true),
                        TextButton(
                          onPressed: _close,
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ProductPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProductHeading('Choose a voucher'),
                              const Text(
                                'Compare the current saving and terms. Selecting an offer updates the checkout quote; it does not reserve a discount.',
                                style: TextStyle(fontSize: 13, height: 1.7),
                              ),
                              if (widget.selectedRevision != null)
                                TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () => _remove(generation),
                                  child: const Text('Remove current voucher'),
                                ),
                            ],
                          ),
                        ),
                        if (_loading) const LinearProgressIndicator(),
                        if (_error != null) ...[
                          Notice(_error!, error: true),
                          TextButton(
                            onPressed: _loading || _choicesCooldown.active
                                ? null
                                : () => _load(),
                            child: Text(
                              _choicesCooldown.active
                                  ? 'Try again in ${_choicesCooldown.remainingSeconds}s'
                                  : 'Try again',
                            ),
                          ),
                        ],
                        if (!_loading &&
                            _error == null &&
                            mapsOf(_page['data']).isEmpty)
                          const ProductPanel(
                            child: Text(
                              'No vouchers are available for this selection.',
                            ),
                          ),
                        if (!_loading && _error == null)
                          for (final offer in mapsOf(_page['data']))
                            ProductPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (offer['revision_id'] ==
                                      widget.selectedRevision)
                                    const Chip(label: Text('Selected voucher')),
                                  if (offer['saving'] != null &&
                                      offer['eligible'] == true)
                                    Text(
                                      'Save ${pesos(offer['saving'])}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  OfferTile(
                                    key: ValueKey(
                                      '$generation:${offer['revision_id']}:${offer['saved_id']}',
                                    ),
                                    offer: offer,
                                    repository: widget.repository,
                                    account: _offersAccount,
                                    onSaved: _load,
                                    onUse:
                                        _loading ||
                                            offer['eligible'] != true ||
                                            positiveInt32ResourceId(
                                                  offer['revision_id'],
                                                ) ==
                                                null
                                        ? null
                                        : () => _choose(offer, generation),
                                  ),
                                ],
                              ),
                            ),
                        if ((_page['last_page'] as num? ?? 1) > 1)
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed:
                                    _loading ||
                                        _choicesCooldown.active ||
                                        _number <= 1
                                    ? null
                                    : () => _changePage(-1, number, generation),
                                child: const Text('Previous'),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'Page ${_page['current_page'] ?? _number} of ${_page['last_page']}',
                                ),
                              ),
                              OutlinedButton(
                                onPressed:
                                    _loading ||
                                        _choicesCooldown.active ||
                                        _number >=
                                            (_page['last_page'] as num? ?? 1)
                                    ? null
                                    : () => _changePage(1, number, generation),
                                child: const Text('Next'),
                              ),
                            ],
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
