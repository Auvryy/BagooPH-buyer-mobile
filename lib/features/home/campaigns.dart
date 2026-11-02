import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'product_card.dart';
import 'advertisement_exposure.dart';

class Campaigns extends StatefulWidget {
  const Campaigns({
    super.key,
    required this.banners,
    required this.session,
    required this.onOpen,
    this.onImpression,
    this.active = true,
  });
  final List<Map<String, dynamic>> banners;
  final WebSession session;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>>? onImpression;
  final bool active;
  @override
  State<Campaigns> createState() => _CampaignsState();
}

class _CampaignsState extends State<Campaigns> {
  final _controller = PageController();
  int _index = 0;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _visibleBanners(
    List<Map<String, dynamic>> banners,
  ) => banners.where((b) => b['image'] is String).take(5).toList();

  String _bannerKey(Map<String, dynamic> banner) =>
      '${banner['id']}-${mapOf(banner['measurement'])['revision_id']}-${banner['image']}';

  @override
  void didUpdateWidget(Campaigns oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _visibleBanners(oldWidget.banners);
    final current = _visibleBanners(widget.banners);
    if (previous.length == current.length &&
        Iterable<int>.generate(current.length).every(
          (index) => _bannerKey(previous[index]) == _bannerKey(current[index]),
        )) {
      return;
    }

    final currentKey = _index < previous.length
        ? _bannerKey(previous[_index])
        : null;
    final retainedIndex = currentKey == null
        ? -1
        : current.indexWhere((banner) => _bannerKey(banner) == currentKey);
    _index = current.isEmpty
        ? 0
        : retainedIndex >= 0
        ? retainedIndex
        : _index.clamp(0, current.length - 1);
    if (current.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(_index);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = _visibleBanners(widget.banners);
    if (banners.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: BagooTheme.rose,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1CCD6)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THE BAGOO WAY TO SHOP',
              style: TextStyle(
                color: BagooTheme.strong,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Everyday value.\nDelivered direct.',
              style: TextStyle(
                color: BagooTheme.ink,
                fontSize: 30,
                height: 1.15,
                letterSpacing: -1,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Local stores. Fresh finds. All in one place.',
              style: TextStyle(
                color: BagooTheme.muted,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: PageView.builder(
              controller: _controller,
              itemCount: banners.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final banner = banners[i];
                final title = banner['title']?.toString().trim();
                final label = title == null || title.isEmpty
                    ? banner['alt_text']?.toString() ?? 'Promotion'
                    : 'Open promotion: $title';
                final href = banner['href']?.toString();
                return Semantics(
                  button: href != null && href.isNotEmpty,
                  label: label,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child: AdvertisementExposure(
                          key: ValueKey(_bannerKey(banner)),
                          active: widget.active && _index == i,
                          onImpression: () => widget.onImpression?.call(banner),
                          builder: (context, ready) => RemoteImage(
                            uri: imageUri(widget.session, banner['image']),
                            fit: BoxFit.contain,
                            onReady: ready,
                          ),
                        ),
                      ),
                      if (href != null && href.isNotEmpty)
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => widget.onOpen(banner),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (banners.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous campaign',
                onPressed: () => _move(-1, banners.length),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_index + 1} of ${banners.length}',
                style: const TextStyle(fontSize: 12),
              ),
              IconButton(
                tooltip: 'Next campaign',
                onPressed: () => _move(1, banners.length),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  void _move(int delta, int count) {
    final next = (_index + delta) % count;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(next);
    } else {
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }
}
