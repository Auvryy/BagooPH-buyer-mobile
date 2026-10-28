import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/device_actions.dart';
import '../home/product_card.dart';
import '../checkout/bag_page.dart';
import '../checkout/checkout_page.dart';
import 'product_model.dart';
import 'product_widgets.dart';
import 'shop_page.dart';
import 'chat_page.dart';
import 'sale_clock.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.repository, required this.slug});
  final BuyerRepository repository;
  final String slug;
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> with WidgetsBindingObserver {
  ProductSelection? _selection;
  String? _error;
  String? _feedback;
  bool _feedbackError = false;
  bool _loading = true;
  bool _busy = false;
  bool _saving = false;
  bool _reminding = false;
  int _image = 0;
  final _quantity = TextEditingController(text: '1');
  final _scroll = ScrollController();
  final _optionsKey = GlobalKey();
  Timer? _refresh;
  int _generation = 0;
  ProductSelection get s => _selection!;
  BuyerRepository get repo => widget.repository;
  bool get _compact =>
      MediaQuery.sizeOf(context).width < 950 ||
      MediaQuery.textScalerOf(context).scale(16) >= 24;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final generation = ++_generation;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await repo.product(widget.slug);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
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
      _refresh?.cancel();
      final offer = mapOf(s.product['sale_offer']);
      if (offer['active'] != null || offer['upcoming'] != null) {
        _refresh = Timer(const Duration(seconds: 30), () {
          if (mounted && !_busy) {
            _load(quiet: true);
          }
        });
      }
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => BagPage(repository: repo)));
    if (mounted) await _load(quiet: true);
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
    if (buyNow && s.page.user == null) {
      _login();
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
    if (s.page.user == null) {
      BuyerActions.login(
        context,
        productSlug: (item ?? s.product)['slug'].toString(),
      );
      return;
    }
    if (!s.approved || _saving) {
      return;
    }
    final id = ((item ?? s.product)['id'] as num).toInt();
    final saved = (s.page.props['savedProductIds'] as List? ?? []).contains(id);
    setState(() => _saving = true);
    try {
      await repo.saveProduct(id, !saved);
      if (!mounted) {
        return;
      }
      final ids = Set<dynamic>.from(
        s.page.props['savedProductIds'] as List? ?? [],
      );
      saved ? ids.remove(id) : ids.add(id);
      setState(() => s.page.props['savedProductIds'] = ids.toList());
    } on BackendException catch (e) {
      if (mounted) {
        _message(e.message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _add(bool buyNow) async {
    if (_busy) {
      return;
    }
    if (buyNow && s.page.user == null) {
      _login();
      return;
    }
    if (buyNow && !s.approved) {
      _message(
        'An active approved buyer account is required for checkout. You may keep shopping and add items to your Bag.',
        error: true,
      );
      return;
    }
    s.quantityText = _quantity.text;
    if (s.quantityError != null) {
      _message(s.quantityError!, error: true);
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    _generation++;
    try {
      final result = await repo.addToBag(
        s.product,
        s.quantity,
        color: s.color,
        size: s.size,
        buyNow: buyNow,
        previousQuantity: s.lineInBag,
      );
      if (!mounted) {
        return;
      }
      if (buyNow) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CheckoutPage(repository: repo, initial: result),
          ),
        );
        if (mounted) {
          await _load(quiet: true);
        }
      } else {
        setState(() => s.page = result);
        _message('${s.quantity} added to your Shopping Bag.');
      }
    } on BackendException catch (e) {
      if (mounted) {
        _message(
          e.fields.isEmpty ? e.message : e.fields.values.join('\n'),
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reminder() async {
    if (s.page.user == null) {
      _login();
      return;
    }
    if (_reminding) {
      return;
    }
    final upcoming = mapOf(mapOf(s.product['sale_offer'])['upcoming']);
    final state = mapOf(s.page.props['saleReminder']);
    if (upcoming['id'] is! num ||
        state['delivered'] == true && state['subscribed'] != true) {
      return;
    }
    setState(() => _reminding = true);
    try {
      final data = await repo.reminder(
        widget.slug,
        (upcoming['id'] as num).toInt(),
        state['subscribed'] != true,
      );
      if (mounted) {
        setState(() => s.page = data);
      }
    } on BackendException catch (e) {
      if (mounted) {
        _message(e.message, error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _reminding = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _quantity.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Product',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
          ? const Center(child: CircularProgressIndicator())
          : _selection == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
                      if (_error != null) Notice(_error!, error: true),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Marketplace / ${mapOf(s.product['category'])['name'] ?? 'Catalogue'} / ${s.product['name']}',
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
                              box.maxWidth >= 850 &&
                                  MediaQuery.textScalerOf(context).scale(16) <
                                      25
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 5, child: _gallery()),
                                    const SizedBox(width: 32),
                                    Expanded(flex: 7, child: _details()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _gallery(),
                                    const SizedBox(height: 24),
                                    _details(),
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
                              avatar: const Icon(Icons.star_outline, size: 18),
                              label: const Text('Reviews & photos'),
                              onPressed: () =>
                                  _section('Reviews & photos', _reviews()),
                            ),
                          ],
                        ),
                      ),
                      _specifications(),
                      _reviews(),
                      if (mapsOf(s.page.props['relatedProducts']).isNotEmpty)
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
              elevation: 6,
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
                      Text(
                        s.priceLabel,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.4,
                          fontWeight: FontWeight.w800,
                          color: BagooTheme.strong,
                        ),
                      ),
                      TextButton(
                        onPressed: _options,
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          s.complete
                              ? '${s.quantity} item${s.quantity == 1 ? '' : 's'}${[s.color, s.size].whereType<String>().isEmpty ? '' : ' · ${[s.color, s.size].whereType<String>().join(' / ')}'} · Edit selection'
                              : 'Choose product options',
                        ),
                      ),
                      _purchaseButtons(),
                    ],
                  ),
                ),
              ),
            ),
          )
        : null,
  );

  Widget _related() => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = productColumns(box.maxWidth + 32, scale);
      final width = (box.maxWidth - (columns - 1) * 14) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final product in mapsOf(s.page.props['relatedProducts']))
            SizedBox(
              width: width,
              height: width + productCardBodyHeight * scale,
              child: ProductCard(
                product: product,
                session: repo.session,
                saved: (s.page.props['savedProductIds'] as List? ?? [])
                    .contains(product['id']),
                saving: _saving,
                saveLabel: s.page.user == null
                    ? 'Sign in to save'
                    : !s.approved
                    ? 'Approval required'
                    : (s.page.props['savedProductIds'] as List? ?? []).contains(
                        product['id'],
                      )
                    ? 'Remove from saved'
                    : 'Save product',
                onSave: s.page.user != null && !s.approved
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
        _busy ||
        s.vacation ||
        s.stock <= 0 ||
        !s.canChangeBag ||
        s.complete && s.maxQuantity < 1;
    final add = OutlinedButton.icon(
      onPressed: disabled ? null : () => _purchase(false),
      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
      label: Text(
        _busy
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
            if (s.gallery.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton.filled(
                    tooltip: 'Previous product photo',
                    onPressed: () => setState(
                      () => _image =
                          (_image - 1 + s.gallery.length) % s.gallery.length,
                    ),
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
                    onPressed: () => setState(
                      () => _image = (_image + 1) % s.gallery.length,
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            if (s.comparison != null &&
                s.comparison! > s.price &&
                !(!s.complete && ProductPrice(s.product).ranged))
              Positioned(
                top: 12,
                right: 12,
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
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (int i = 0; i < s.gallery.length; i++)
            Semantics(
              selected: _image == i,
              button: true,
              label: 'Product photo ${i + 1}',
              child: SizedBox.square(
                dimension: 64,
                child: OutlinedButton(
                  onPressed: () => setState(() => _image = i),
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
                    borderRadius: BorderRadius.circular(6),
                    child: ExcludeSemantics(
                      child: RemoteImage(
                        uri: imageUri(repo.session, s.gallery[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const Divider(height: 28),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: s.page.user != null && !s.approved || _saving
                ? null
                : _save,
            icon: Icon(
              (s.page.props['savedProductIds'] as List? ?? []).contains(
                    s.product['id'],
                  )
                  ? Icons.favorite
                  : Icons.favorite_border,
              size: 18,
            ),
            label: Text(
              _saving
                  ? 'Saving…'
                  : s.page.user == null
                  ? 'Sign in to save'
                  : !s.approved
                  ? 'Approval required'
                  : (s.page.props['savedProductIds'] as List? ?? []).contains(
                      s.product['id'],
                    )
                  ? 'Remove from saved'
                  : 'Save product',
            ),
          ),
          const Text(
            'BagooPH Buyer Protection',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BagooTheme.strong,
            ),
          ),
        ],
      ),
    ],
  );
  Widget _details() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
      Text(
        s.product['name'].toString(),
        style: const TextStyle(
          fontSize: 25,
          height: 1.3,
          fontWeight: FontWeight.w800,
        ),
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
          Text(
            '${s.product['verified_review_count'] ?? 0} Verified ratings',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '${s.product['sales_count'] ?? 0} Sold',
            style: const TextStyle(fontSize: 12),
          ),
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
                fontSize: 28,
                fontWeight: FontWeight.w900,
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
      if (s.colors.isNotEmpty) ...[
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
      if (s.sizes.isNotEmpty) ...[
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
            s.stock <= 0
                ? 'This selection is out of stock'
                : '${s.maxQuantity} more available to add · ${s.totalInBag} in your Bag',
            style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
          if (s.complete && s.quantityError != null)
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
        child: RemoteImage(uri: uri),
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
                  _reminding ||
                      mapOf(s.page.props['saleReminder'])['delivered'] ==
                              true &&
                          mapOf(s.page.props['saleReminder'])['subscribed'] !=
                              true
                  ? null
                  : _reminder,
              icon: const Icon(Icons.notifications_outlined),
              label: Text(
                _reminding
                    ? 'Saving…'
                    : mapOf(s.page.props['saleReminder'])['subscribed'] == true
                    ? 'Remove reminder'
                    : mapOf(s.page.props['saleReminder'])['delivered'] == true
                    ? 'Reminder sent'
                    : 'Remind me',
              ),
            ),
          ],
          SaleClock(
            offer: offer,
            onBoundary: () {
              if (!_busy && !_loading) _load(quiet: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _shop() {
    final shop = mapOf(s.product['shop']);
    final stats = mapOf(s.page.props['shopStats']);
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
                  child: RemoteImage(uri: imageUri(repo.session, shop['logo'])),
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
                onPressed: shop['slug'] == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ShopPage(
                            repository: repo,
                            slug: shop['slug'].toString(),
                          ),
                        ),
                      ),
                child: const Text('View Shop'),
              ),
              FilledButton.icon(
                onPressed: () {
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
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.key,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BagooTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.value.toString().isEmpty
                        ? 'Not listed'
                        : row.value.toString(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                onSignIn: s.page.user == null ? _login : null,
                canSave: s.page.user == null || s.approved,
                onUse: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BagPage(
                      repository: repo,
                      voucherCode: o['code']?.toString(),
                    ),
                  ),
                ),
              ),
          ],
          const ProductHeading('Product Description'),
          Text(
            p['description']?.toString() ?? 'No description provided.',
            style: const TextStyle(fontSize: 14, height: 1.7),
          ),
        ],
      ),
    );
  }

  Widget _reviews() {
    final reviews = mapsOf(s.product['reviews']);
    final photos = reviews
        .expand(
          (review) => (review['images'] as List? ?? []).whereType<String>(),
        )
        .toList();
    return ProductPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductHeading('Customer Reviews & Photos'),
          if (photos.isNotEmpty) ...[
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
              Text(
                '(${s.product['verified_review_count'] ?? 0} Verified Reviews)',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const Divider(height: 32),
          if (reviews.isEmpty)
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
                      for (final photo
                          in (r['images'] as List? ?? []).whereType<String>())
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
                              label:
                                  'Open review photo ${(r['images'] as List).indexOf(photo) + 1}',
                              excludeSemantics: true,
                              child: RemoteImage(
                                uri: imageUri(repo.session, photo),
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
