import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../home/search_controller.dart';
import '../products/product_page.dart';
import '../products/shop_page.dart';
import '../profile/order_detail_page.dart';
import '../profile/profile_repository.dart';
import '../profile/purchases_section.dart';
import '../profile/returns_page.dart';
import '../promotions/promotion_page.dart';

class BuyerDestinationRouter {
  const BuyerDestinationRouter._();

  static Future<void> openHref(
    BuildContext context,
    BuyerRepository repository,
    String? href, {
    required ValueChanged<SearchFilters>? onSearch,
    required ValueChanged<String>? onProfileSection,
    bool closeForTabDestination = false,
  }) async {
    if (href == null || href.trim().isEmpty) {
      throw const BackendException('This update has no available destination.');
    }
    final target = repository.session.resolve(href);
    final segments = target.pathSegments;

    if (segments.isEmpty) {
      _openSearch(context, target, onSearch, closeForTabDestination);
      return;
    }

    if (segments.first == 'advertisement' || segments.first == 'promotions') {
      final page = await repository.document(target.toString());
      repository.requireNoErrors(page);
      if (!context.mounted) return;
      await _openPage(
        context,
        repository,
        page,
        fallbackUri: target,
        onSearch: onSearch,
        onProfileSection: onProfileSection,
        closeForTabDestination: closeForTabDestination,
      );
      return;
    }

    if (segments.length >= 2 &&
        segments.first == 'buyer' &&
        segments[1] == 'search') {
      _openSearch(context, target, onSearch, closeForTabDestination);
      return;
    }
    if (segments.first == 'buyer' &&
        segments.length >= 2 &&
        segments[1] == 'profile') {
      _openProfile(
        context,
        _profileSection(target.queryParameters['tab']),
        onProfileSection,
        closeForTabDestination,
      );
      return;
    }
    if (segments.first == 'buyer' &&
        segments.length == 2 &&
        segments[1] == 'orders') {
      _openProfile(context, 'orders', onProfileSection, closeForTabDestination);
      return;
    }
    if (segments.first == 'buyer' &&
        segments.length == 3 &&
        segments[1] == 'orders') {
      await _openOrder(context, repository, segments[2]);
      return;
    }
    if (segments.first == 'buyer-returns') {
      if (segments.length == 1) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ReturnsPage(repository: ProfileRepository(repository)),
          ),
        );
        return;
      }
      if (segments.length == 2) {
        await _openReturn(context, repository, segments[1]);
        return;
      }
      if (segments.length == 4 &&
          segments[1] == 'orders' &&
          segments[3] == 'create') {
        final orderId = int.tryParse(segments[2]);
        if (orderId != null && orderId > 0) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReturnsPage(
                repository: ProfileRepository(repository),
                orderId: orderId,
              ),
            ),
          );
          return;
        }
      }
    }
    if (segments.first == 'wallet' &&
        segments.length == 2 &&
        segments[1] == 'payments') {
      _openProfile(context, 'wallet', onProfileSection, closeForTabDestination);
      return;
    }
    if (segments.first == 'wallet' &&
        segments.length == 3 &&
        segments[1] == 'payments') {
      final id = int.tryParse(segments[2]);
      if (id != null && id > 0) {
        await openWalletPayment(context, ProfileRepository(repository), id);
        return;
      }
    }
    if ((segments.first == 'buyer' &&
            segments.length == 3 &&
            segments[1] == 'product') ||
        (segments.first == 'product' && segments.length == 2)) {
      await _openProduct(context, repository, segments.last);
      return;
    }
    if (segments.first == 'shop' && segments.length == 2) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShopPage(repository: repository, slug: segments[1]),
        ),
      );
      return;
    }
    if (segments.first == 'account' &&
        segments.length >= 2 &&
        segments[1] == 'status') {
      _openProfile(
        context,
        'overview',
        onProfileSection,
        closeForTabDestination,
      );
      return;
    }

    throw const BackendException(
      'This update cannot open a buyer screen in the app yet.',
    );
  }

  static Future<void> _openPage(
    BuildContext context,
    BuyerRepository repository,
    WebPage page, {
    required Uri fallbackUri,
    required ValueChanged<SearchFilters>? onSearch,
    required ValueChanged<String>? onProfileSection,
    required bool closeForTabDestination,
  }) async {
    repository.requireNoErrors(page);
    if (page.user != null && page.user?['role'] != 'buyer') {
      throw const BackendException(
        'This destination is not available to your buyer account.',
      );
    }
    final uri = page.url == null
        ? fallbackUri
        : repository.session.resolve(page.url!);
    switch (page.component) {
      case 'Buyer/Promotion':
        if (page.props['promotion'] is! Map ||
            page.props['products'] is! List) {
          throw const BackendException('This promotion is unavailable.');
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (pageContext) => PromotionPage(
              repository: repository,
              initial: page,
              onOpenDestination: (href) => openHref(
                pageContext,
                repository,
                href,
                onSearch: onSearch,
                onProfileSection: onProfileSection,
                closeForTabDestination: true,
              ),
              onProfileSection: (section) {
                Navigator.of(pageContext).pop();
                onProfileSection?.call(section);
              },
            ),
          ),
        );
        return;
      case 'Buyer/ProductDetail':
        final slug = mapOf(page.props['product'])['slug']?.toString();
        if (slug == null || slug.isEmpty) {
          throw const BackendException('This product is unavailable.');
        }
        await _openProduct(context, repository, slug);
        return;
      case 'Marketplace/ShopDetail':
        final slug = mapOf(page.props['shop'])['slug']?.toString();
        if (slug == null || slug.isEmpty) {
          throw const BackendException('This shop is unavailable.');
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ShopPage(repository: repository, slug: slug),
          ),
        );
        return;
      case 'Buyer/Search':
        _openSearch(context, uri, onSearch, closeForTabDestination);
        return;
      case 'Buyer/Profile':
        _openProfile(
          context,
          _profileSection(uri.queryParameters['tab']),
          onProfileSection,
          closeForTabDestination,
        );
        return;
      case 'Buyer/OrderDetail':
        final id = mapOf(page.props['order'])['id'];
        if (id is! num || id <= 0) {
          throw const BackendException('This order is unavailable.');
        }
        await _openOrder(context, repository, '${id.toInt()}');
        return;
      case 'Returns/Show':
        final id = mapOf(page.props['returnCase'])['id'];
        if (id is! num || id <= 0) {
          throw const BackendException('This return is unavailable.');
        }
        await _openReturn(context, repository, '${id.toInt()}');
        return;
      default:
        throw const BackendException(
          'This destination is not available in the buyer app yet.',
        );
    }
  }

  static SearchFilters _filters(Uri uri) => SearchFilters(
    query: uri.queryParameters['search'] ?? '',
    category: uri.queryParameters['category'] ?? '',
    location: uri.queryParameters['location'] ?? '',
    minimum: uri.queryParameters['min_price'] ?? '',
    maximum: uri.queryParameters['max_price'] ?? '',
    rating: uri.queryParameters['rating'] ?? '',
    inStock: ['1', 'true'].contains(uri.queryParameters['in_stock']),
    sort: uri.queryParameters['sort'] ?? 'relevance',
  );

  static String _profileSection(String? tab) => switch (tab) {
    'personal' ||
    'emails' ||
    'password' ||
    'identity' ||
    'sessions' ||
    'addresses' ||
    'wallet' ||
    'vouchers' ||
    'orders' => tab!,
    _ => 'overview',
  };

  static void _openSearch(
    BuildContext context,
    Uri uri,
    ValueChanged<SearchFilters>? onSearch,
    bool close,
  ) {
    if (onSearch == null) {
      throw const BackendException(
        'Search is unavailable from this screen. Return to Home and try again.',
      );
    }
    if (close) Navigator.of(context).pop();
    onSearch(_filters(uri));
  }

  static void _openProfile(
    BuildContext context,
    String section,
    ValueChanged<String>? onProfileSection,
    bool close,
  ) {
    if (onProfileSection == null) {
      throw const BackendException(
        'Profile is unavailable from this screen. Return to Home and try again.',
      );
    }
    if (close) Navigator.of(context).pop();
    onProfileSection(section);
  }

  static Future<void> _openProduct(
    BuildContext context,
    BuyerRepository repository,
    String slug,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProductPage(repository: repository, slug: slug),
    ),
  );

  static Future<void> _openOrder(
    BuildContext context,
    BuyerRepository repository,
    String rawId,
  ) async {
    final id = int.tryParse(rawId);
    if (id == null || id <= 0) {
      throw const BackendException('This order is unavailable.');
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          repository: ProfileRepository(repository),
          orderId: id,
        ),
      ),
    );
  }

  static Future<void> _openReturn(
    BuildContext context,
    BuyerRepository repository,
    String rawId,
  ) async {
    final id = int.tryParse(rawId);
    if (id == null || id <= 0) {
      throw const BackendException('This return is unavailable.');
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReturnsPage(repository: ProfileRepository(repository), caseId: id),
      ),
    );
  }
}
