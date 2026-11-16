import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_page.dart';

/// A Bagoo sale event: a countdown on the server's clock, claimable vouchers and real product discounts.
class CampaignPage extends StatefulWidget {
  const CampaignPage({
    super.key,
    required this.repository,
    required this.initial,
  });

  final BuyerRepository repository;
  final WebPage initial;

  @override
  State<CampaignPage> createState() => _CampaignPageState();
}

String voucherHeadline(Map<String, dynamic> voucher) {
  final value = amount(voucher['discount_value']) ?? 0;
  final whole = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return switch (voucher['discount_type']) {
    'percent' => '$whole% off',
    'free_shipping' => '₱$whole off shipping',
    _ => '₱$whole off',
  };
}

/// Time left until [target], measured on the server's clock captured with the page.
Duration remainingOnServerClock(
  DateTime target,
  DateTime serverNow,
  DateTime deviceAtLoad,
  DateTime deviceNow,
) {
  final serverClock = serverNow.add(deviceNow.difference(deviceAtLoad));
  final left = target.difference(serverClock);
  return left.isNegative ? Duration.zero : left;
}

class _CampaignPageState extends State<CampaignPage> {
  late WebPage _page = widget.initial;
  late DateTime _loadedAt = DateTime.now();
  Timer? _ticker;
  Duration _left = Duration.zero;
  final Set<int> _claiming = <int>{};
  bool _claimingAll = false;
  int? _category;
  bool _reloading = false;

  Map<String, dynamic> get _campaign => mapOf(_page.props['campaign']);
  List<Map<String, dynamic>> get _vouchers => mapsOf(_page.props['vouchers'])
      .where(
        (row) => positiveResourceId(row['id']) != null && row['code'] is String,
      )
      .toList();
  List<Map<String, dynamic>> get _products =>
      mapsOf(_page.props['products'])
          .where((row) => row['slug'] is String && row['name'] is String)
          .toList();
  List<Map<String, dynamic>> get _categories =>
      mapsOf(_page.props['categories'])
          .where(
            (row) =>
                positiveResourceId(row['id']) != null && row['name'] is String,
          )
          .toList();
  String get _status => _campaign['status']?.toString() ?? 'ended';
  bool get _live => _status == 'live';

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final target = DateTime.tryParse(
      (_status == 'upcoming' ? _campaign['starts_at'] : _campaign['ends_at'])
              ?.toString() ??
          '',
    );
    final serverNow = DateTime.tryParse(
      _page.props['serverNow']?.toString() ?? '',
    );
    if (target == null || serverNow == null || _status == 'ended') {
      if (mounted) setState(() => _left = Duration.zero);
      return;
    }
    final left = remainingOnServerClock(
      target,
      serverNow,
      _loadedAt,
      DateTime.now(),
    );
    if (!mounted) return;
    setState(() => _left = left);
    if (left == Duration.zero && !_reloading) unawaited(_reload());
  }

  Future<void> _reload() async {
    final slug = _campaign['slug']?.toString();
    if (slug == null || slug.isEmpty) return;
    _reloading = true;
    try {
      final page = await widget.repository.session.page('/campaign/$slug');
      if (!mounted) return;
      setState(() {
        _page = page;
        _loadedAt = DateTime.now();
      });
      _tick();
    } on BackendException {
      // Keep the current page; the next action or pull-to-refresh tries again.
    } finally {
      _reloading = false;
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _claim(Map<String, dynamic> voucher) async {
    final id = positiveResourceId(voucher['id']);
    if (id == null || _claiming.contains(id) || voucher['claimed'] == true) {
      return;
    }
    if (_page.user == null) {
      _say('Sign in to claim vouchers.');
      return;
    }
    setState(() => _claiming.add(id));
    try {
      final result = await widget.repository.session.jsonPost(
        '/campaign/vouchers/$id/claim',
        const {},
      );
      _say(result['message']?.toString() ?? 'Voucher claimed.');
      await _reload();
    } on BackendException catch (error) {
      _say(error.message);
      await _reload();
    } finally {
      if (mounted) setState(() => _claiming.remove(id));
    }
  }

  Future<void> _claimAll() async {
    final eventId = positiveResourceId(_campaign['id']);
    if (eventId == null || _claimingAll) return;
    if (_page.user == null) {
      _say('Sign in to claim vouchers.');
      return;
    }
    setState(() => _claimingAll = true);
    try {
      final result = await widget.repository.session.jsonPost(
        '/campaign/$eventId/claim-all',
        const {},
      );
      _say(result['message']?.toString() ?? 'Vouchers claimed.');
    } on BackendException catch (error) {
      _say(error.message);
    } finally {
      await _reload();
      if (mounted) setState(() => _claimingAll = false);
    }
  }

  Future<void> _openEvent(String slug) async {
    if (slug == _campaign['slug']) return;
    try {
      final page = await widget.repository.session.page('/campaign/$slug');
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              CampaignPage(repository: widget.repository, initial: page),
        ),
      );
    } on BackendException catch (error) {
      _say(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _campaign['title']?.toString() ?? 'Sale event';
    final banner = imageUri(widget.repository.session, _campaign['banner_url']);
    final products = _category == null
        ? _products
        : _products
              .where(
                (p) =>
                    positiveResourceId(mapOf(p['category'])['id']) == _category,
              )
              .toList();
    final claimable = _vouchers
        .where((v) => v['claimed'] != true && v['sold_out'] != true)
        .length;
    final events = mapsOf(_page.props['allCampaigns'])
        .where((e) => e['slug'] is String)
        .toList();

    return Scaffold(
      backgroundColor: BagooTheme.canvas,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 5
                : constraints.maxWidth >= 600
                ? 3
                : 2;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (banner != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 47 / 22,
                      child: RemoteImage(uri: banner, fit: BoxFit.cover),
                    ),
                  ),
                const SizedBox(height: 12),
                _Header(campaign: _campaign, status: _status, left: _left),
                if (events.length > 1) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final current = event['slug'] == _campaign['slug'];
                        return ChoiceChip(
                          label: Text(
                            event['status'] == 'upcoming'
                                ? '${event['badge']} · Soon'
                                : '${event['badge']}',
                          ),
                          selected: current,
                          onSelected: (_) =>
                              _openEvent(event['slug'].toString()),
                        );
                      },
                    ),
                  ),
                ],
                if (_vouchers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Vouchers',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: BagooTheme.ink,
                          ),
                        ),
                      ),
                      if (_live && claimable > 1)
                        FilledButton(
                          onPressed: _claimingAll ? null : _claimAll,
                          child: Text(
                            _claimingAll ? 'Claiming…' : 'Claim all $claimable',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final voucher in _vouchers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _VoucherCard(
                        voucher: voucher,
                        live: _live,
                        claiming: _claiming.contains(
                          positiveResourceId(voucher['id']),
                        ),
                        onClaim: () => _claim(voucher),
                      ),
                    ),
                  const Text(
                    'Claimed vouchers apply at checkout when your order qualifies.',
                    style: TextStyle(fontSize: 12, color: BagooTheme.muted),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Deals · ${_products.length}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: BagooTheme.ink,
                  ),
                ),
                if (_categories.length > 1) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _category == null,
                          onSelected: (_) => setState(() => _category = null),
                        ),
                        for (final category in _categories) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(category['name'].toString()),
                            selected:
                                _category == positiveResourceId(category['id']),
                            onSelected: (_) => setState(
                              () => _category = positiveResourceId(
                                category['id'],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (products.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BagooTheme.line),
                    ),
                    child: Text(
                      _status == 'ended' ? 'This event has ended.' : 'Shops are adding their discounts. Check back soon.',
                      style: const TextStyle(color: BagooTheme.muted),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.62,
                    ),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _DealTile(
                        product: product,
                        live: _live,
                        session: widget.repository.session,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ProductPage(
                              repository: widget.repository,
                              slug: product['slug'].toString(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.campaign,
    required this.status,
    required this.left,
  });
  final Map<String, dynamic> campaign;
  final String status;
  final Duration left;

  @override
  Widget build(BuildContext context) {
    Widget unit(int value, String label) => Column(
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 42),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: BagooTheme.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
        ),
      ],
    );
    final days = left.inDays,
        hours = left.inHours % 24,
        minutes = left.inMinutes % 60,
        seconds = left.inSeconds % 60;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BagooTheme.rose,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: BagooTheme.crimson,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              campaign['badge']?.toString() ?? 'DEAL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            campaign['title']?.toString() ?? '',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: BagooTheme.ink,
            ),
          ),
          const SizedBox(height: 12),
          if (status == 'ended')
            const Text(
              'This event has ended',
              style: TextStyle(
                color: BagooTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Semantics(
              label:
                  '${status == 'upcoming' ? 'Starts' : 'Ends'} in $days days $hours hours $minutes minutes',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Text(
                      status == 'upcoming' ? 'Starts in' : 'Ends in',
                      style: const TextStyle(
                        color: BagooTheme.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (days > 0) ...[
                      unit(days, 'days'),
                      const SizedBox(width: 6),
                    ],
                    unit(hours, 'hrs'),
                    const SizedBox(width: 6),
                    unit(minutes, 'min'),
                    const SizedBox(width: 6),
                    unit(seconds, 'sec'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  const _VoucherCard({
    required this.voucher,
    required this.live,
    required this.claiming,
    required this.onClaim,
  });
  final Map<String, dynamic> voucher;
  final bool live, claiming;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final minSpend = amount(voucher['min_spend']) ?? 0;
    final cap = amount(voucher['max_discount']) ?? 0;
    final limit = positiveResourceId(voucher['claim_limit']);
    final claimedCount = (amount(voucher['claimed_count']) ?? 0).toInt();
    final soldOut = voucher['sold_out'] == true;
    final claimed = voucher['claimed'] == true;
    final terms = [
      minSpend > 0 ? 'Min. spend ${pesos(minSpend)}' : 'No minimum spend',
      if (voucher['discount_type'] != 'fixed' && cap > 0) 'up to ${pesos(cap)}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BagooTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            voucher['issuer'] == 'platform'
                ? 'Bagoo voucher'
                : (voucher['shop_name']?.toString() ?? 'Shop voucher'),
            style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
          ),
          const SizedBox(height: 4),
          Text(
            voucherHeadline(voucher),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: BagooTheme.ink,
            ),
          ),
          Text(terms, style: const TextStyle(color: BagooTheme.muted)),
          Text(
            voucher['code'].toString(),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: BagooTheme.muted,
            ),
          ),
          if (limit != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (claimedCount / limit).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: BagooTheme.crimson,
                backgroundColor: BagooTheme.line,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              soldOut
                  ? 'All claimed'
                  : '${limit - claimedCount} of $limit left',
              style: const TextStyle(fontSize: 12, color: BagooTheme.muted),
            ),
          ],
          const SizedBox(height: 10),
          if (claimed)
            Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 18, color: Color(0xFF15803D)),
                  SizedBox(width: 6),
                  Text(
                    'Claimed',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: claiming || soldOut || !live ? null : onClaim,
                child: Text(
                  claiming
                      ? 'Claiming…'
                      : soldOut
                      ? 'All claimed'
                      : live
                      ? 'Claim'
                      : 'Opens when the event starts',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DealTile extends StatelessWidget {
  const _DealTile({
    required this.product,
    required this.live,
    required this.session,
    required this.onTap,
  });
  final Map<String, dynamic> product;
  final bool live;
  final WebSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = imageUri(session, product['image']);
    final discount = (amount(product['discount_pct']) ?? 0).toInt();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BagooTheme.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      RemoteImage(uri: image, fit: BoxFit.cover)
                    else
                      const ColoredBox(color: BagooTheme.canvas),
                    if (discount > 0)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: BagooTheme.crimson,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-$discount%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: BagooTheme.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        pesos(product['price']),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: BagooTheme.ink,
                        ),
                      ),
                      Text(
                        pesos(product['regular_price']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: BagooTheme.muted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      if (!live)
                        const Text(
                          'Sale price when the event starts',
                          style: TextStyle(
                            fontSize: 11,
                            color: BagooTheme.muted,
                          ),
                        ),
                      if (mapOf(product['shop'])['name'] is String)
                        Text(
                          mapOf(product['shop'])['name'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: BagooTheme.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
