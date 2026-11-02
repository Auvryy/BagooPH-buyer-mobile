import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/count_metadata.dart';
import '../../core/verification_prompt.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/buyer_repository.dart';
import '../../core/strict_datetime.dart';
import '../../core/numeric_input.dart';
import '../../core/resource_ids.dart';
import '../../core/retry_cooldown.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/device_actions.dart';
import '../../core/cached_catalogue_notice.dart';
import '../../core/foreground_refresh.dart';
import '../home/product_card.dart';
import '../home/catalogue_loading.dart';
import '../checkout/bag_page.dart';
import '../checkout/checkout_page.dart';
import 'product_model.dart';
import 'product_widgets.dart';
import 'shop_page.dart';
import 'chat_page.dart';
import 'sale_clock.dart';

List<String> _reviewImageUrls(Object? value) => value is List
    ? value.whereType<String>().where((path) => path.trim().isNotEmpty).toList()
    : const [];

List<Map<String, dynamic>>? _completeProductReviews(Object? raw) {
  if (raw is! List) return null;
  final rows = <Map<String, dynamic>>[];
  final ids = <int>{};
  for (final row in raw) {
    if (row is! Map || row.keys.any((key) => key is! String)) return null;
    final review = Map<String, dynamic>.from(row);
    final id = positiveResourceId(review['id']);
    final rating = review['rating'];
    final createdAt = review['created_at'];
    final comment = review['comment'];
    if (id == null ||
        !ids.add(id) ||
        rating is! int ||
        rating < 1 ||
        rating > 5 ||
        createdAt is! String ||
        strictDateTime(createdAt) == null ||
        comment != null && comment is! String ||
        review['verified_purchase'] is! bool) {
      return null;
    }
    final buyer = review['buyer'];
    if (buyer != null &&
        (buyer is! Map ||
            buyer.keys.any((key) => key is! String) ||
            buyer['name'] is! String)) {
      return null;
    }
    final options = review['purchased_options'];
    if (options != null &&
        (options is! Map ||
            options.keys.any((key) => key is! String) ||
            options.values.any((value) => value != null && value is! String))) {
      return null;
    }
    final reply = review['reply'];
    if (reply != null) {
      if (reply is! Map || reply.keys.any((key) => key is! String)) {
        return null;
      }
      final replyText = reply['text'];
      final replyCreatedAt = reply['created_at'];
      final replyUpdatedAt = reply['updated_at'];
      if (replyText is! String ||
          replyText.trim().isEmpty ||
          replyCreatedAt is! String ||
          strictDateTime(replyCreatedAt) == null ||
          replyUpdatedAt != null &&
              (replyUpdatedAt is! String ||
                  strictDateTime(replyUpdatedAt) == null) ||
          reply['shop_name'] != null && reply['shop_name'] is! String) {
        return null;
      }
    }
    rows.add(review);
  }
  return rows;
}

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.repository, required this.slug});
  final BuyerRepository repository;
  final String slug;
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> with WidgetsBindingObserver {
  late BuyerAccountScope _checkoutAccount;
  late int _identityEpoch;
  ProductSelection? _selection;
  String? _error;
  String? _feedback;
  bool _feedbackError = false;
  bool _loading = true;
  bool _busy = false;
  bool _saving = false;
  bool _reminding = false;
  late final RetryCooldown _reminderCooldown;
  bool _approvalPromptOpen = false;
  int _image = 0;
  final _quantity = TextEditingController(text: '1');
  final _scroll = ScrollController();
  final _thumbnails = ScrollController();
  final _detailsKey = GlobalKey();
  final _optionsKey = GlobalKey();
  late final ForegroundRead _updates;
  int _reads = 0;
  int _generation = 0;
  DateTime? _verifiedAt;
  ProductSelection get s => _selection!;
  List<Map<String, dynamic>> get _relatedProducts =>
      completeRelatedProducts(s.page.props['relatedProducts']) ?? const [];
  BuyerRepository get repo => widget.repository;
  bool get _sessionBindingCurrent =>
      identical(_checkoutAccount.session, repo.session) &&
      _identityEpoch == repo.session.identityEpoch;
  bool get _accountCurrent =>
      _sessionBindingCurrent && _checkoutAccount.isCurrent;
  bool get _hasSale {
    if (_selection == null) return false;
    final offer = mapOf(s.product['sale_offer']);
    return mapOf(offer['active']).isNotEmpty ||
        mapOf(offer['upcoming']).isNotEmpty;
  }

  bool get _compact =>
      MediaQuery.sizeOf(context).width < 950 ||
      MediaQuery.textScalerOf(context).scale(16) >= 24;
  @override
  void initState() {
    super.initState();
    _checkoutAccount = BuyerAccountScope(repo.session);
    _identityEpoch = repo.session.identityEpoch;
    _reminderCooldown = RetryCooldown(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _updates = ForegroundRead(
      interval: const Duration(seconds: 30),
      refreshInitially: false,
      read: (ticket) async {
        if (_reads > 0 || _busy || _saving || _reminding) {
          return ReadOutcome.success;
        }
        await _load(quiet: true, ticket: ticket);
        return _error == null ? ReadOutcome.success : ReadOutcome.retry;
      },
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository == widget.repository &&
        oldWidget.slug == widget.slug) {
      return;
    }
    _generation++;
    _reminderCooldown.clear(notify: false);
    _checkoutAccount.invalidate();
    _checkoutAccount = BuyerAccountScope(repo.session);
    _identityEpoch = repo.session.identityEpoch;
    _selection = null;
    _error = null;
    _feedback = null;
    _feedbackError = false;
    _loading = true;
    _busy = false;
    _saving = false;
    _reminding = false;
    _image = 0;
    _verifiedAt = null;
    _quantity.text = '1';
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_hasSale &&
        _reads == 0 &&
        !_busy &&
        (ModalRoute.isCurrentOf(context) ?? true)) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false, ReadTicket? ticket}) async {
    final identityChanged = !_sessionBindingCurrent;
    if (!quiet || identityChanged) {
      setState(() {
        if (identityChanged) {
          _checkoutAccount.invalidate();
          _checkoutAccount = BuyerAccountScope(repo.session);
          _identityEpoch = repo.session.identityEpoch;
          _reminderCooldown.clear(notify: false);
          _selection = null;
          _feedback = null;
          _feedbackError = false;
          _busy = false;
          _saving = false;
          _reminding = false;
          _image = 0;
          _verifiedAt = null;
          _quantity.text = '1';
        }
        _loading = true;
        _error = null;
      });
    }
    _reads++;
    final generation = ++_generation;
    final epoch = repo.session.identityEpoch;
    final cacheGeneration = repo.catalogueCache.generation;
    try {
      final fresh = repo.product(widget.slug);
      if (_selection == null) {
        unawaited(
          repo.cachedProduct(widget.slug).then<void>((cached) {
            if (cached != null &&
                mounted &&
                generation == _generation &&
                _loading &&
                _selection == null &&
                epoch == repo.session.identityEpoch &&
                cacheGeneration == repo.catalogueCache.generation) {
              setState(() => _selection = ProductSelection(cached));
            }
          }, onError: (Object _, StackTrace _) {}),
        );
      }
      final page = await fresh;
      if (!mounted || generation != _generation || ticket?.isCurrent == false) {
        return;
      }
      if (epoch != repo.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Refresh to continue.',
          status: 401,
        );
      }
      if (!page.isCached && page.user != null) {
        _checkoutAccount.check(page: page);
      }
      setState(() {
        if (!page.isCached) _verifiedAt = DateTime.now();
        if (_selection == null) {
          _selection = ProductSelection(page);
        } else {
          s.page = page;
        }
        if (!s.colors.any((o) => o['name'] == s.color)) {
          s.color = null;
        }
        if (!s.sizes.any((o) => o['name'] == s.size)) {
          s.size = null;
        }
        _image = _image.clamp(0, (s.gallery.length - 1).clamp(0, 999));
        _error = null;
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation && ticket?.isCurrent != false) {
        setState(() {
          _error = e.message;
          if ([401, 403, 404, 410, 419].contains(e.status)) {
            _selection = null;
            _busy = false;
            _saving = false;
            _reminding = false;
          } else if (_selection != null) {
            s.page = WebPage(
              s.page.component,
              s.page.props,
              cachedAt: s.page.cachedAt ?? _verifiedAt,
            );
          }
        });
      }
    } finally {
      _reads--;
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _ensureCurrentAccount() async {
    if (_accountCurrent) return true;
    await _load(quiet: true);
    return false;
  }

  bool _mutationIsCurrent(ProductSelection selection, int epoch) =>
      mounted &&
      epoch == repo.session.identityEpoch &&
      identical(_selection, selection) &&
      _accountCurrent;

  Future<void> _recoverAfterSessionChange(int epoch) async {
    if (mounted &&
        (epoch != repo.session.identityEpoch || !_checkoutAccount.isCurrent)) {
      await _load(quiet: true);
    }
  }

  void _message(String text, {bool error = false}) {
    setState(() {
      _feedback = text;
      _feedbackError = error;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: error
            ? null
            : SnackBarAction(label: 'View Bag', onPressed: _viewBag),
      ),
    );
  }

  Future<void> _viewBag() async {
    if (_selection == null ||
        !await _ensureCurrentAccount() ||
        !mounted ||
        _selection == null ||
        !_accountCurrent) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BagPage(repository: repo, account: _checkoutAccount),
      ),
    );
    if (mounted && _accountCurrent) await _load(quiet: true);
  }

  Future<void> _options() async {
    if (_optionsKey.currentContext == null && _scroll.hasClients) {
      _scroll.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || _optionsKey.currentContext == null) return;
    await Scrollable.ensureVisible(
      _optionsKey.currentContext!,
      alignment: .08,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
  }

  void _purchase(bool buyNow) {
    if (_approvalPromptOpen) return;
    if (!_accountCurrent) {
      unawaited(_load(quiet: true));
      return;
    }
    if (_selection == null) return;
    if (s.page.isCached) return;
    if (buyNow && s.page.user == null) {
      _login();
      return;
    }
    if (buyNow && !s.approved) {
      unawaited(_add(true));
      return;
    }
    if (!s.complete) {
      _message('Choose each product option before continuing.', error: true);
      _options();
      return;
    }
    _add(buyNow);
  }

  void _section(String title, Widget child) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [child],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _login() => BuyerActions.login(context, productSlug: widget.slug);
  Future<void> _save([Map<String, dynamic>? item]) async {
    if (_selection == null ||
        !await _ensureCurrentAccount() ||
        !mounted ||
        _selection == null ||
        !_accountCurrent) {
      return;
    }
    final selection = s;
    if (selection.page.isCached) return;
    if (selection.page.user == null) {
      BuyerActions.login(
        context,
        productSlug: (item ?? selection.product)['slug'].toString(),
      );
      return;
    }
    if (!selection.approved || _saving) {
      return;
    }
    final id = positiveResourceId((item ?? selection.product)['id']);
    if (id == null) {
      _message(
        'This product could not be confirmed. Refresh and try again.',
        error: true,
      );
      return;
    }
    final saved = positiveResourceIds(selection.page.props['savedProductIds'])
        .contains(id);
    final epoch = repo.session.identityEpoch;
    setState(() => _saving = true);
    try {
      await repo.saveProduct(id, !saved);
      if (!_mutationIsCurrent(selection, epoch)) {
        await _recoverAfterSessionChange(epoch);
        return;
      }
      final ids = positiveResourceIds(selection.page.props['savedProductIds']);
      saved ? ids.remove(id) : ids.add(id);
      setState(() => selection.page.props['savedProductIds'] = ids.toList());
    } on BackendException catch (e) {
      if (_mutationIsCurrent(selection, epoch)) {
        _message(e.message, error: true);
      } else {
        await _recoverAfterSessionChange(epoch);
      }
    } finally {
      if (mounted && identical(_selection, selection)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _add(bool buyNow) async {
    if (_selection == null ||
        !await _ensureCurrentAccount() ||
        !mounted ||
        _selection == null ||
        !_accountCurrent) {
      return;
    }
    final selection = s;
    if (selection.page.isCached) return;
    if (_busy) {
      return;
    }
    if (buyNow && selection.page.user == null) {
      _login();
      return;
    }
    if (buyNow && !selection.approved) {
      if (_approvalPromptOpen) return;
      _approvalPromptOpen = true;
      final epoch = repo.session.identityEpoch;
      try {
        final review = await showBuyerVerificationPrompt(
          context,
          selection.page.user!,
        );
        if (review &&
            mounted &&
            _accountCurrent &&
            identical(_selection, selection)) {
          _checkoutAccount.check(page: selection.page);
          if (mounted) BuyerActions.reviewVerification(context);
        }
      } on BackendException {
        await _recoverAfterSessionChange(epoch);
      } finally {
        _approvalPromptOpen = false;
      }
      return;
    }
    selection.quantityText = _quantity.text;
    if (selection.quantityError != null) {
      _message(selection.quantityError!, error: true);
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    _generation++;
    final epoch = repo.session.identityEpoch;
    try {
      if (buyNow) {
        _checkoutAccount.check(page: selection.page);
      }
      final result = await repo.addToBag(
        selection.product,
        selection.quantity,
        color: selection.color,
        size: selection.size,
        buyNow: buyNow,
        previousQuantity: selection.lineInBag,
      );
      if (!mounted) return;
      if (!_mutationIsCurrent(selection, epoch)) {
        await _recoverAfterSessionChange(epoch);
        return;
      }
      if (selection.page.user != null || result.user != null) {
        _checkoutAccount.check(page: result);
      }
      if (buyNow) {
        _checkoutAccount.check(page: result);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CheckoutPage(
              repository: repo,
              initial: result,
              account: _checkoutAccount,
            ),
          ),
        );
        if (mounted) {
          setState(() => _busy = false);
          await _load(quiet: true);
        }
      } else {
        setState(() => selection.page = result);
        _message('${selection.quantity} added to your Shopping Bag.');
      }
    } on BackendException catch (e) {
      if (_mutationIsCurrent(selection, epoch)) {
        _message(
          e.fields.isEmpty ? e.message : e.fields.values.join('\n'),
          error: true,
        );
      } else {
        await _recoverAfterSessionChange(epoch);
      }
    } finally {
      if (mounted && identical(_selection, selection)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reminder() async {
    if (_selection == null ||
        !await _ensureCurrentAccount() ||
        !mounted ||
        _selection == null ||
        !_accountCurrent) {
      return;
    }
    if (_reminderCooldown.active) return;
    final selection = s;
    if (selection.page.isCached) return;
    if (selection.page.user == null) {
      _login();
      return;
    }
    if (_reminding) {
      return;
    }
    final upcoming = mapOf(mapOf(selection.product['sale_offer'])['upcoming']);
    final state = mapOf(selection.page.props['saleReminder']);
    final upcomingId = positiveResourceId(upcoming['id']);
    if (upcomingId == null ||
        state['delivered'] == true && state['subscribed'] != true) {
      return;
    }
    final epoch = repo.session.identityEpoch;
    setState(() => _reminding = true);
    try {
      final data = await repo.reminder(
        widget.slug,
        upcomingId,
        state['subscribed'] != true,
      );
      if (!_mutationIsCurrent(selection, epoch)) {
        await _recoverAfterSessionChange(epoch);
        return;
      }
      _checkoutAccount.check(page: data);
      setState(() => selection.page = data);
    } on BackendException catch (e) {
      if (_mutationIsCurrent(selection, epoch)) {
        if (e.status == 429) {
          _reminderCooldown.start(e.data, retryAt: e.retryAt, notify: false);
        }
        _message(e.message, error: true);
      } else {
        await _recoverAfterSessionChange(epoch);
      }
    } finally {
      if (mounted && identical(_selection, selection)) {
        setState(() => _reminding = false);
      }
    }
  }

  @override
  void dispose() {
    _checkoutAccount.invalidate();
    _reminderCooldown.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _updates.dispose();
    _quantity.dispose();
    _scroll.dispose();
    _thumbnails.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ForegroundRefresh(
    controller: _updates,
    enabled: _hasSale && !_busy && !_saving && !_reminding,
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: BagooTheme.strong,
        foregroundColor: Colors.white,
        title: const Text(
          'Product',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Share product',
            onPressed: _selection == null
                ? null
                : () async {
                    try {
                      await shareBuyerProduct(
                        context,
                        repo.session.resolve(
                          '/product/${Uri.encodeComponent(widget.slug)}',
                        ),
                        s.product['name']?.toString() ?? 'Bagoo product',
                      );
                    } on BackendException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sharing is unavailable. Use Copy product link.',
                            ),
                          ),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: 'Copy product link',
            onPressed: _selection == null
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: repo.session
                            .resolve(
                              '/product/${Uri.encodeComponent(widget.slug)}',
                            )
                            .toString(),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Product link copied.')),
                      );
                    }
                  },
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'Shopping Bag',
            onPressed: _viewBag,
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _selection == null
            ? const ProductLoadingPlaceholder()
            : _selection == null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Notice(_error ?? 'Product unavailable.', error: true),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (s.page.cachedAt case final savedAt?)
                          CachedCatalogueNotice(
                            savedAt: savedAt,
                            refreshing: _loading,
                            onRefresh: _loading || _busy
                                ? null
                                : () => _load(quiet: true),
                          ),
                        if (_error != null) Notice(_error!, error: true),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Marketplace / ${mapOf(s.product['category'])['name'] ?? 'Catalogue'}',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: BagooTheme.muted,
                            ),
                          ),
                        ),
                        ProductPanel(
                          child: LayoutBuilder(
                            builder: (context, box) =>
                                box.maxWidth >= 600 &&
                                    MediaQuery.textScalerOf(context).scale(16) <
                                        25
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 5, child: _gallery()),
                                      const SizedBox(width: 32),
                                      Expanded(flex: 7, child: _details()),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _productTitle(),
                                      const SizedBox(height: 16),
                                      _gallery(),
                                      const SizedBox(height: 20),
                                      _details(showTitle: false),
                                    ],
                                  ),
                          ),
                        ),
                        _shop(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ActionChip(
                                avatar: const Icon(
                                  Icons.list_alt_outlined,
                                  size: 18,
                                ),
                                label: const Text('Specifications'),
                                onPressed: () => _section(
                                  'Product specifications',
                                  _specifications(),
                                ),
                              ),
                              ActionChip(
                                avatar: const Icon(
                                  Icons.star_outline,
                                  size: 18,
                                ),
                                label: const Text('Reviews & photos'),
                                onPressed: () =>
                                    _section('Reviews & photos', _reviews()),
                              ),
                            ],
                          ),
                        ),
                        _specifications(),
                        _reviews(),
                        if (_relatedProducts.isNotEmpty)
                          ProductPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const ProductHeading('You may also like'),
                                _related(),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar:
          _selection != null &&
              _compact &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                shape: const Border(top: BorderSide(color: BagooTheme.line)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _purchaseSummary(),
                        const SizedBox(height: 8),
                        _purchaseButtons(),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
    ),
  );

  Widget _purchaseSummary() {
    final selection = s.complete
        ? '${s.quantity} item${s.quantity == 1 ? '' : 's'}${[s.color, s.size].whereType<String>().isEmpty ? '' : ' · ${[s.color, s.size].whereType<String>().join(' / ')}'} · Edit selection'
        : 'Choose product options';
    final price = Text(
      s.priceLabel,
      style: const TextStyle(
        fontSize: 22,
        height: 1.4,
        fontWeight: FontWeight.w800,
        color: BagooTheme.strong,
      ),
    );
    final edit = TextButton(
      onPressed: _options,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(selection),
    );
    return LayoutBuilder(
      builder: (context, box) =>
          box.maxWidth >= 300 && MediaQuery.textScalerOf(context).scale(16) < 24
          ? Row(
              children: [
                Expanded(child: price),
                const SizedBox(width: 12),
                Expanded(child: edit),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [price, edit],
            ),
    );
  }

  Widget _related() => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = productColumns(box.maxWidth + 32, scale);
      final width = (box.maxWidth - (columns - 1) * 14) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final product in _relatedProducts)
            SizedBox(
              width: width,
              height: width + productCardBodyHeight * scale,
              child: ProductCard(
                product: product,
                session: repo.session,
                saved:
                    _accountCurrent &&
                    positiveResourceIds(s.page.props['savedProductIds'])
                        .contains(product['id']),
                saving: _saving,
                saveLabel: !_accountCurrent
                    ? 'Refresh to continue'
                    : s.page.isCached
                    ? 'Connect to save'
                    : s.page.user == null
                    ? 'Sign in to save'
                    : !s.approved
                    ? 'Approval required'
                    : positiveResourceIds(s.page.props['savedProductIds'])
                          .contains(product['id'])
                    ? 'Remove from saved'
                    : 'Save product',
                onSave:
                    !_accountCurrent ||
                        s.page.isCached ||
                        s.page.user != null && !s.approved
                    ? null
                    : () => _save(product),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProductPage(
                      repository: repo,
                      slug: product['slug'].toString(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _purchaseButtons() {
    final disabled =
        !_accountCurrent ||
        s.page.isCached ||
        _busy ||
        s.vacation ||
        s.stock <= 0 ||
        !s.canChangeBag ||
        s.complete && s.maxQuantity < 1;
    final add = OutlinedButton.icon(
      onPressed: disabled ? null : () => _purchase(false),
      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
      label: Text(
        !_accountCurrent
            ? 'Refresh to continue'
            : s.page.isCached
            ? 'Connect to shop'
            : _busy
            ? 'Adding…'
            : s.vacation
            ? 'Shop on vacation'
            : !s.canChangeBag
            ? 'Account restricted'
            : s.stock <= 0 || s.complete && s.maxQuantity < 1
            ? 'Unavailable'
            : 'Add to Bag',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: BagooTheme.strong,
        backgroundColor: BagooTheme.rose,
        side: const BorderSide(color: BagooTheme.crimson),
      ),
    );
    final buy = FilledButton(
      onPressed: disabled ? null : () => _purchase(true),
      child: const Text('Buy Now'),
    );
    return LayoutBuilder(
      builder: (context, box) =>
          box.maxWidth < 300 || MediaQuery.textScalerOf(context).scale(16) >= 24
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [add, const SizedBox(height: 8), buy],
            )
          : Row(
              children: [
                Expanded(child: add),
                const SizedBox(width: 12),
                Expanded(child: buy),
              ],
            ),
    );
  }

  Widget _gallery() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: const Color(0xFFF1F5F9),
                child: InkWell(
                  onTap: s.gallery.isEmpty
                      ? null
                      : () => viewImage(
                          context,
                          repo.session,
                          s.gallery[_image],
                          s.product['name'].toString(),
                        ),
                  child: Semantics(
                    label: s.gallery.isEmpty
                        ? 'No product photo available'
                        : 'Open product photo ${_image + 1} of ${s.gallery.length}',
                    excludeSemantics: true,
                    child: RemoteImage(
                      uri: s.gallery.isEmpty
                          ? null
                          : imageUri(repo.session, s.gallery[_image]),
                      thumbnail: true,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BagooTheme.ink,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s.gallery.isEmpty
                      ? 'No product photo'
                      : 'Photo ${_image + 1} of ${s.gallery.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: _saveLabel,
                onPressed:
                    !_accountCurrent ||
                        s.page.isCached ||
                        s.page.user != null && !s.approved ||
                        _saving
                    ? null
                    : _save,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: Colors.white,
                  foregroundColor: BagooTheme.strong,
                ),
                icon: Icon(
                  _accountCurrent &&
                          positiveResourceIds(s.page.props['savedProductIds'])
                              .contains(s.product['id'])
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
            ),
            if (s.gallery.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton.filled(
                    tooltip: 'Previous product photo',
                    onPressed: () =>
                        _selectImage(_image - 1 + s.gallery.length),
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
              ),
            if (s.gallery.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton.filled(
                    tooltip: 'Next product photo',
                    onPressed: () => _selectImage(_image + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            if (s.comparison != null &&
                s.comparison! > s.price &&
                !(!s.complete && ProductPrice(s.product).ranged))
              Positioned(
                top: 8,
                left: 8,
                child: Chip(
                  backgroundColor: BagooTheme.crimson,
                  label: Text(
                    '-${((s.comparison! - s.price) / s.comparison! * 100).round()}% OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (s.gallery.length > 1) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: ListView.separated(
            controller: _thumbnails,
            scrollDirection: Axis.horizontal,
            itemCount: s.gallery.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Semantics(
              selected: _image == i,
              button: true,
              label: 'Product photo ${i + 1}',
              child: Center(
                child: SizedBox.square(
                  dimension: 64,
                  child: OutlinedButton(
                    onPressed: () => _selectImage(i),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(
                        color: _image == i
                            ? BagooTheme.crimson
                            : BagooTheme.border,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ExcludeSemantics(
                        child: RemoteImage(
                          uri: imageUri(repo.session, s.gallery[i]),
                          thumbnail: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  String get _saveLabel => !_accountCurrent
      ? 'Refresh to continue'
      : s.page.isCached
      ? 'Connect to save'
      : _saving
      ? 'Saving product'
      : s.page.user == null
      ? 'Sign in to save'
      : !s.approved
      ? 'Approval required'
      : positiveResourceIds(s.page.props['savedProductIds'])
            .contains(s.product['id'])
      ? 'Remove from saved'
      : 'Save product';

  void _selectImage(int index) {
    if (s.gallery.isEmpty) return;
    setState(() => _image = index % s.gallery.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_thumbnails.hasClients) return;
      final start = _image * 72.0;
      final viewport = _thumbnails.position.viewportDimension;
      if (start < _thumbnails.offset ||
          start + 64 > _thumbnails.offset + viewport) {
        final target = start.clamp(0.0, _thumbnails.position.maxScrollExtent);
        if (MediaQuery.disableAnimationsOf(context)) {
          _thumbnails.jumpTo(target);
        } else {
          _thumbnails.animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Widget _productTitle() => Semantics(
    header: true,
    child: Text(
      s.product['name'].toString(),
      style: const TextStyle(
        fontSize: 21,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -.3,
      ),
    ),
  );

  Widget _details({bool showTitle = true}) => Column(
    key: _detailsKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showTitle) ...[_productTitle(), const SizedBox(height: 12)],
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (mapOf(s.product['shop'])['review_status'] == 'approved' ||
              mapOf(s.product['shop'])['status'] == 'active')
            const Chip(
              label: Text(
                'APPROVED SHOP',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
              backgroundColor: BagooTheme.crimson,
            ),
          Text(
            'SKU: ${s.combination['sku'] ?? s.product['sku'] ?? 'Not provided'}',
            style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            ratingLabel(s.product['rating']),
            style: const TextStyle(
              color: BagooTheme.strong,
              fontWeight: FontWeight.w700,
            ),
          ),
          Stars(s.product['rating']),
          if (nonNegativeCount(s.product['verified_review_count'])
              case final int count)
            Text(
              '$count verified ratings',
              style: const TextStyle(fontSize: 12),
            ),
          if (nonNegativeCount(s.product['sales_count']) case final int count)
            Text('$count sold', style: const TextStyle(fontSize: 12)),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        [
          if (s.product['condition'] != null)
            s.product['condition'].toString().replaceAll('_', ' '),
          if (s.product['weight_kg'] != null) '${s.product['weight_kg']} kg',
          if (s.product['length_cm'] != null &&
              s.product['width_cm'] != null &&
              s.product['height_cm'] != null)
            '${s.product['length_cm']} × ${s.product['width_cm']} × ${s.product['height_cm']} cm',
        ].join(' · '),
        style: const TextStyle(
          fontSize: 12,
          height: 1.6,
          color: BagooTheme.muted,
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              s.priceLabel,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: BagooTheme.crimson,
              ),
            ),
            if (s.comparison != null && s.comparison! > s.price && s.complete)
              Text(
                pesos(s.comparison),
                style: const TextStyle(
                  color: BagooTheme.muted,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Delivery updates: Follow recorded parcel checkpoints after ordering.\nPayment: Cash on Delivery or Bagoo Wallet. Delivery fees are confirmed at checkout.',
        style: TextStyle(fontSize: 12, height: 1.7, color: BagooTheme.muted),
      ),
      if (s.vacation)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Notice(
            'On vacation. This shop has paused new purchases.',
            error: true,
          ),
        ),
      if (s.product['purchase_limit'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Limit ${s.product['purchase_limit']} per buyer. ${s.page.props['purchaseAllowance'] ?? s.product['purchase_limit']} remaining.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      _sales(),
      SizedBox(key: _optionsKey, height: 1),
      if (!s.inventoryCountsValid)
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Notice(
            'Available stock and Bag quantities could not be confirmed. Refresh this product.',
            error: true,
          ),
        ),
      if (s.inventoryCountsValid && s.colors.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          '${s.variants['option1_name'] ?? 'Color / Edition'}: ${s.color ?? 'Choose an option'}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: s.colors
              .map(
                (o) => ChoiceChip(
                  selected: s.color == o['name'],
                  showCheckmark: false,
                  side: BorderSide(
                    color: s.color == o['name']
                        ? BagooTheme.strong
                        : BagooTheme.line,
                  ),
                  labelStyle: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    color: s.color == o['name']
                        ? BagooTheme.strong
                        : BagooTheme.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  avatar: _optionAvatar(o),
                  label: Text(o['name'].toString()),
                  selectedColor: BagooTheme.rose,
                  onSelected: _busy || !s.colorAvailable(o['name'].toString())
                      ? null
                      : (_) => setState(() {
                          s.color = o['name'].toString();
                          if (s.size != null && !s.sizeAvailable(s.size!)) {
                            s.size = null;
                          }
                          if (o['image_url'] != null &&
                              s.gallery.contains(o['image_url'])) {
                            _image = s.gallery.indexOf(o['image_url']);
                          }
                          _feedback = null;
                        }),
                ),
              )
              .toList(),
        ),
      ],
      if (s.inventoryCountsValid && s.sizes.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          '${s.variants['option2_name'] ?? 'Specification / Size'}: ${s.size ?? 'Choose an option'}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: s.sizes
              .map(
                (o) => ChoiceChip(
                  selected: s.size == o['name'],
                  showCheckmark: false,
                  side: BorderSide(
                    color: s.size == o['name']
                        ? BagooTheme.strong
                        : BagooTheme.line,
                  ),
                  labelStyle: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    color: s.size == o['name']
                        ? BagooTheme.strong
                        : BagooTheme.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  label: Text(o['name'].toString()),
                  selectedColor: BagooTheme.rose,
                  onSelected: _busy || !s.sizeAvailable(o['name'].toString())
                      ? null
                      : (_) => setState(() {
                          s.size = o['name'].toString();
                          _feedback = null;
                        }),
                ),
              )
              .toList(),
        ),
      ],
      const SizedBox(height: 24),
      const Text(
        'Quantity',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Decrease quantity',
                onPressed: _busy || s.quantity <= 1 || s.maxQuantity < 1
                    ? null
                    : () => setState(() {
                        _quantity.text = '${s.quantity - 1}';
                        s.quantityText = _quantity.text;
                      }),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _quantity,
                  enabled: !_busy && s.maxQuantity > 0,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [unsignedIntegerFormatter],
                  maxLength: 2,
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: 'Units',
                    contentPadding: EdgeInsets.all(8),
                  ),
                  onChanged: (v) => setState(() => s.quantityText = v),
                ),
              ),
              IconButton(
                tooltip: 'Increase quantity',
                onPressed: _busy || s.quantity >= s.maxQuantity
                    ? null
                    : () => setState(() {
                        _quantity.text = '${s.quantity + 1}';
                        s.quantityText = _quantity.text;
                      }),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text(
            !s.inventoryCountsValid
                ? 'Availability could not be confirmed'
                : s.stock <= 0
                ? 'This selection is out of stock'
                : '${s.maxQuantity} more available to add · ${s.totalInBag} in your Bag',
            style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
          if (s.inventoryCountsValid && s.complete && s.quantityError != null)
            Text(
              s.quantityError!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Color(0xFFBE123C),
              ),
            ),
        ],
      ),
      if (_feedback != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Notice(_feedback!, error: _feedbackError),
        ),
      const SizedBox(height: 24),
      if (!_compact) _purchaseButtons(),
    ],
  );
  Widget? _optionAvatar(Map<String, dynamic> option) {
    final uri = imageUri(repo.session, option['image_url']);
    if (uri != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: RemoteImage(uri: uri, thumbnail: true),
      );
    }
    final hex = option['hex']?.toString().replaceFirst('#', '') ?? '';
    final value = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return value == null
        ? null
        : Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | value),
              shape: BoxShape.circle,
              border: Border.all(color: BagooTheme.border),
            ),
          );
  }

  Widget _sales() {
    final offer = mapOf(s.product['sale_offer']);
    final active = mapOf(offer['active']);
    final upcoming = mapOf(offer['upcoming']);
    final reminder = _accountCurrent
        ? mapOf(s.page.props['saleReminder'])
        : <String, dynamic>{};
    if (active.isEmpty && upcoming.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BagooTheme.rose,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active.isNotEmpty) ...[
            Text(
              active['name']?.toString() ?? 'Product sale',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: BagooTheme.strong,
              ),
            ),
            Text(
              'Ends ${readableDateTime(active['ends_at'])}',
              style: const TextStyle(fontSize: 12),
            ),
            if (active['kind'] == 'flash')
              Text(
                '${active['remaining_quantity']} promotional units remain. Additional units use the price shown at checkout.',
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
          ],
          if (upcoming.isNotEmpty) ...[
            Text(
              upcoming['name']?.toString() ?? 'Upcoming sale',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('Starts ${readableDateTime(upcoming['starts_at'])}'),
            TextButton.icon(
              onPressed:
                  !_accountCurrent ||
                      s.page.isCached ||
                      _reminding ||
                      _reminderCooldown.active ||
                      reminder['delivered'] == true &&
                          reminder['subscribed'] != true
                  ? null
                  : _reminder,
              icon: const Icon(Icons.notifications_outlined),
              label: Text(
                _reminding
                    ? 'Saving…'
                    : !_accountCurrent
                    ? 'Refresh to continue'
                    : _reminderCooldown.active
                    ? 'Try again in ${_reminderCooldown.remainingSeconds}s'
                    : reminder['subscribed'] == true
                    ? 'Remove reminder'
                    : reminder['delivered'] == true
                    ? 'Reminder sent'
                    : 'Remind me',
              ),
            ),
          ],
          SaleClock(
            offer: offer,
            onBoundary: () {
              if (_updates.active && _reads == 0) _updates.refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _shop() {
    final shop = mapOf(s.product['shop']);
    final stats = mapOf(s.page.props['shopStats']);
    final rawSlug = shop['slug'];
    final shopSlug =
        rawSlug is String &&
            rawSlug.trim().isNotEmpty &&
            rawSlug == rawSlug.trim()
        ? rawSlug
        : null;
    return ProductPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RemoteImage(
                    uri: imageUri(repo.session, shop['logo']),
                    thumbnail: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop['name']?.toString() ?? 'Shop',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      shop['city']?.toString() ?? 'Location unavailable',
                      style: const TextStyle(
                        fontSize: 12,
                        color: BagooTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: shopSlug == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ShopPage(repository: repo, slug: shopSlug),
                        ),
                      ),
                child: const Text('View Shop'),
              ),
              FilledButton.icon(
                onPressed: s.page.isCached
                    ? null
                    : () {
                        if (s.page.user == null) {
                          _login();
                        } else if (!s.approved) {
                          _message(
                            'Chat requires an approved buyer account.',
                            error: true,
                          );
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChatPage(
                                repository: repo,
                                product: s.product,
                                userId: s.page.user!['id'] as int,
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Chat Now'),
              ),
            ],
          ),
          const Divider(height: 28),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Text('Ratings: ${ratingLabel(stats['rating'])}'),
              Text('Products: ${stats['products_count'] ?? 'Not provided'}'),
              Text(
                'Review reply rate: ${stats['response_rate'] ?? 'No verified reviews'}',
              ),
              Text('Shop opened: ${readableDate(stats['joined'])}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _specifications() {
    final p = s.product;
    final dimensions = [
      'length_cm',
      'width_cm',
      'height_cm',
    ].map((k) => amount(p[k])).toList();
    final rows = {
      'Department': mapOf(p['category'])['name'] ?? 'Not provided',
      'Store categories': mapsOf(p['store_categories'])
          .map((c) => c['name'])
          .join(', '),
      'Brand': p['brand'] ?? 'Not provided',
      'Condition': p['condition'] ?? 'Not provided',
      'Declared weight': p['weight_kg'] == null
          ? 'Not provided'
          : '${p['weight_kg']} kg',
      'Dimensions (L × W × H)': dimensions.every((n) => n != null && n > 0)
          ? '${dimensions.join(' × ')} cm'
          : 'Not provided',
      'Available stock': s.totalStock > 0
          ? '${s.totalStock} units'
          : 'Out of stock',
      'Seller location': mapOf(p['shop'])['city'] ?? 'Not provided',
    };
    return ProductPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductHeading('Product specifications'),
          for (final row in rows.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LayoutBuilder(
                builder: (context, box) {
                  final label = Text(
                    row.key,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: BagooTheme.muted,
                    ),
                  );
                  final value = Text(
                    row.value.toString().isEmpty
                        ? 'Not listed'
                        : row.value.toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                  if (box.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(12) >= 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [label, const SizedBox(height: 3), value],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: box.maxWidth * .38, child: label),
                      Expanded(child: value),
                    ],
                  );
                },
              ),
            ),
          const Text(
            'Weight and dimensions are declared by the seller. Delivery fees are confirmed at checkout.',
            style: TextStyle(
              fontSize: 12,
              color: BagooTheme.muted,
              height: 1.6,
            ),
          ),
          const Divider(height: 32),
          if (mapsOf(s.page.props['shopOffers']).isNotEmpty) ...[
            const ProductHeading('Shop offers'),
            for (final o in mapsOf(s.page.props['shopOffers']))
              OfferTile(
                offer: o,
                repository: repo,
                account: _checkoutAccount,
                onSignIn: s.page.user == null ? _login : null,
                canSave: s.page.user == null || s.approved,
                onUse: !_accountCurrent
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BagPage(
                            repository: repo,
                            account: _checkoutAccount,
                            voucherCode: o['code']?.toString(),
                          ),
                        ),
                      ),
              ),
          ],
          const ProductHeading('Product Description'),
          SizedBox(
            width: double.infinity,
            child: Text(
              p['description']?.toString() ?? 'No description provided.',
              textAlign: TextAlign.start,
              style: const TextStyle(fontSize: 13, height: 1.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviews() {
    final parsedReviews = _completeProductReviews(s.product['reviews']);
    final reviews = parsedReviews ?? const <Map<String, dynamic>>[];
    final reviewsValid = parsedReviews != null;
    final photos = reviews
        .expand((review) => _reviewImageUrls(review['images']))
        .toList();
    return ProductPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductHeading('Customer Reviews & Photos'),
          if (reviewsValid && photos.isNotEmpty) ...[
            const Text(
              'Customer photo gallery',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < photos.length; index++)
                  SizedBox.square(
                    dimension: 72,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => viewImage(
                        context,
                        repo.session,
                        photos[index],
                        'Customer photo ${index + 1} of ${photos.length}',
                      ),
                      child: Semantics(
                        label: 'Open customer photo ${index + 1}',
                        child: RemoteImage(
                          uri: imageUri(repo.session, photos[index]),
                          thumbnail: true,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ratingLabel(s.product['rating']),
                style: const TextStyle(
                  fontSize: 22,
                  color: BagooTheme.crimson,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Stars(s.product['rating']),
              if (nonNegativeCount(s.product['verified_review_count'])
                  case final int count)
                Text(
                  '($count verified reviews)',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          const Divider(height: 32),
          if (reviews.isEmpty && s.page.isCached)
            const Text(
              'Refresh from Bagoo to load customer reviews.',
              style: TextStyle(color: BagooTheme.muted, height: 1.5),
            )
          else if (!reviewsValid)
            const Text(
              'Customer reviews could not be confirmed. Refresh this product.',
              style: TextStyle(color: BagooTheme.muted, height: 1.5),
            )
          else if (reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.auto_awesome_outlined, color: BagooTheme.crimson),
                  SizedBox(height: 12),
                  Text(
                    'No customer reviews yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Reviews from verified customers will appear here.',
                    style: TextStyle(fontSize: 12, color: BagooTheme.muted),
                  ),
                ],
              ),
            ),
          if (reviewsValid)
            for (final r in reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          mapOf(r['buyer'])['name']?.toString() ?? 'Shopper',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          r['verified_purchase'] == true
                              ? 'Verified Purchase'
                              : 'Unverified legacy review',
                          style: const TextStyle(
                            fontSize: 11,
                            color: BagooTheme.muted,
                          ),
                        ),
                        Text(
                          readableDate(r['created_at']),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Stars(r['rating']),
                    if (r['purchased_options'] != null)
                      Text(
                        'Purchased option: ${mapOf(r['purchased_options']).values.whereType<String>().join(' · ')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      r['comment']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (index, photo) in _reviewImageUrls(
                          r['images'],
                        ).indexed)
                          SizedBox.square(
                            dimension: 64,
                            child: OutlinedButton(
                              onPressed: () => viewImage(
                                context,
                                repo.session,
                                photo,
                                'Review photo',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ),
                              child: Semantics(
                                label: 'Open review photo ${index + 1}',
                                excludeSemantics: true,
                                child: RemoteImage(
                                  uri: imageUri(repo.session, photo),
                                  thumbnail: true,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (r['reply'] != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: BagooTheme.canvas,
                          border: Border.all(color: BagooTheme.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seller reply · ${mapOf(r['reply'])['shop_name'] ?? mapOf(s.product['shop'])['name']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: BagooTheme.strong,
                              ),
                            ),
                            Text(
                              mapOf(r['reply'])['text']?.toString() ?? '',
                              style: const TextStyle(fontSize: 12, height: 1.6),
                            ),
                            Text(
                              'Posted ${readableDateTime(mapOf(r['reply'])['created_at'])}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (mapOf(r['reply'])['updated_at'] != null &&
                                mapOf(r['reply'])['updated_at'] !=
                                    mapOf(r['reply'])['created_at'])
                              Text(
                                'Updated ${readableDateTime(mapOf(r['reply'])['updated_at'])}',
                                style: const TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
