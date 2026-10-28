import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../home/search_controller.dart';
import '../products/product_page.dart';
import '../products/shop_page.dart';
import '../profile/order_detail_page.dart';
import '../profile/profile_repository.dart';
import '../profile/account_status_page.dart';
import '../profile/purchases_section.dart';
import '../profile/returns_page.dart';
import '../promotions/promotion_page.dart';
import '../tracking/parcel_tracking_page.dart';
import 'engagement_repository.dart';
import 'buyer_link.dart';
import '../../core/buyer_actions.dart';
import '../auth/password_link_page.dart';
import '../auth/email_verification_link_page.dart';
import '../collections/saved_products_page.dart';
import '../collections/followed_shops_page.dart';
import '../notifications/notifications_page.dart';
import '../profile/inbox_page.dart';
import '../checkout/bag_page.dart';
import '../checkout/checkout_page.dart';

class BuyerDestinationRouter {
  const BuyerDestinationRouter._();

  static Future<void> openNotification(
    BuildContext context,
    BuyerRepository repository,
    String id,
    int ownerId, {
    required ValueChanged<SearchFilters>? onSearch,
    required ValueChanged<String>? onProfileSection,
    bool closeForTabDestination = false,
    bool Function()? isCurrent,
  }) async {
    final page = await BuyerEngagementRepository(repository)
        .openNotification(id, ownerId);
    if (!context.mounted || isCurrent?.call() == false) return;
    await _openPage(
      context,
      repository,
      page,
      fallbackUri: repository.session.resolve(page.url ?? '/notifications'),
      onSearch: onSearch,
      onProfileSection: onProfileSection,
      closeForTabDestination: closeForTabDestination,
    );
  }

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
    final link = BuyerLink.parse(target, repository.session.origin);
    final segments = target.pathSegments;
    if (link.kind == BuyerLinkKind.passwordReset) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => PasswordLinkPage(
            repository: repository,
            initialLink: target,
            checkGuest: true,
            onComplete: () => BuyerActions.login(routeContext),
          ),
        ),
      );
      return;
    }
    if (link.kind == BuyerLinkKind.emailVerification) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              EmailVerificationLinkPage(repository: repository, link: target),
        ),
      );
      return;
    }
    if (target.path == '/cart') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BagPage(
            repository: repository,
            voucherCode:
                target.queryParameters['voucher'] ??
                target.queryParameters['voucher_code'],
          ),
        ),
      );
      return;
    }
    if (target.path == '/checkout') {
      final page = await repository.document(target.toString());
      repository.requireNoErrors(page);
      if (page.component != 'Checkout/Index' ||
          page.props['items'] is! List ||
          page.props['checkoutToken'] is! String) {
        throw const BackendException(
          'Checkout is unavailable. Review your Bag and sign in if needed.',
        );
      }
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CheckoutPage(repository: repository, initial: page),
          ),
        );
      }
      return;
    }
    if (target.path == '/account/security' ||
        target.path == '/account/settings' ||
        target.path == '/buyer/addresses' ||
        target.path == '/pending-approval' ||
        target.path == '/verify-email') {
      final section = {
        '/account/security': 'sessions',
        '/account/settings': 'personal',
        '/buyer/addresses': 'addresses',
        '/pending-approval': 'identity',
        '/verify-email': 'emails',
      }[target.path]!;
      _openProfile(context, section, onProfileSection, closeForTabDestination);
      return;
    }
    if (target.path == '/buyer/messages') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InboxPage(repository: ProfileRepository(repository)),
        ),
      );
      return;
    }
    if ([
      '/buyer/saved-products',
      '/buyer/followed-shops',
      '/notifications',
    ].contains(target.path)) {
      final page = await repository.currentSession();
      if (page?.user?['id'] is! num) {
        throw const BackendException(
          'Sign in to your buyer account to open this screen.',
          status: 401,
        );
      }
      if (!context.mounted) return;
      final owner = (page!.user!['id'] as num).toInt();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => target.path == '/buyer/saved-products'
              ? SavedProductsPage(
                  repository: repository,
                  ownerId: owner,
                  onSearch: onSearch,
                )
              : target.path == '/buyer/followed-shops'
              ? FollowedShopsPage(
                  repository: repository,
                  ownerId: owner,
                  onSearch: onSearch,
                )
              : NotificationsPage(
                  repository: repository,
                  ownerId: owner,
                  onSearch: onSearch,
                  onProfileSection: onProfileSection,
                ),
        ),
      );
      return;
    }

    if (segments.isNotEmpty &&
        segments.first == 'track' &&
        segments.length <= 2) {
      final number = segments.length == 2
          ? segments[1]
          : target.queryParameters['number'] ??
                target.queryParameters['tracking_number'] ??
                target.queryParameters['q'];
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ParcelTrackingPage(repository: repository, initialNumber: number),
        ),
      );
      return;
    }

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
        _profileSection(
          target.fragment.isNotEmpty
              ? target.fragment
              : target.queryParameters['tab'],
        ),
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
        final orderId = buyerLinkId(segments[2]);
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
      final id = buyerLinkId(segments[2]);
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
    if (segments.first == 'shop' &&
        (segments.length == 2 ||
            segments.length == 4 && segments[2] == 'categories')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShopPage(
            repository: repository,
            slug: segments[1],
            storeCategory: segments.length == 4 ? segments[3] : 'all',
          ),
        ),
      );
      return;
    }
    if (segments.first == 'account' &&
        segments.length >= 2 &&
        segments[1] == 'status') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => AccountStatusPage(
            repository: repository,
            onIdentity: onProfileSection == null
                ? null
                : () {
                    Navigator.pop(routeContext);
                    if (closeForTabDestination) Navigator.pop(context);
                    onProfileSection('identity');
                  },
          ),
        ),
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
      case 'Auth/AccountStatus':
        await openHref(
          context,
          repository,
          '/account/status',
          onSearch: onSearch,
          onProfileSection: onProfileSection,
          closeForTabDestination: closeForTabDestination,
        );
        return;
      case 'Public/Tracking':
        final number = page.props['searchedNumber'];
        if (number is! String) {
          throw const BackendException(
            'This tracking destination is unavailable.',
          );
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ParcelTrackingPage(
              repository: repository,
              initialNumber: number,
            ),
          ),
        );
        return;
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
          _profileSection(
            uri.fragment.isNotEmpty ? uri.fragment : uri.queryParameters['tab'],
          ),
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

  static SearchFilters _filters(Uri uri) {
    for (final key in ['min_price', 'max_price']) {
      if (SearchFilters.priceError(uri.queryParameters[key]) != null) {
        throw const BackendException(
          'This search link has an invalid price filter.',
        );
      }
    }
    return SearchFilters(
      query: uri.queryParameters['search'] ?? '',
      category: uri.queryParameters['category'] ?? '',
      location: uri.queryParameters['location'] ?? '',
      minimum: uri.queryParameters['min_price'] ?? '',
      maximum: uri.queryParameters['max_price'] ?? '',
      rating:
          [
            '',
            '3',
            '4',
            '4.5',
            '5',
          ].contains(uri.queryParameters['rating'] ?? '')
          ? uri.queryParameters['rating'] ?? ''
          : '',
      inStock: ['1', 'true'].contains(uri.queryParameters['in_stock']),
      sort: searchSorts.containsKey(uri.queryParameters['sort'])
          ? uri.queryParameters['sort']!
          : 'relevance',
    );
  }

  static String _profileSection(String? tab) => switch (tab) {
    'account-personal' || 'account' => 'personal',
    'account-password' => 'password',
    'account-identity' ||
    'account-verification' ||
    'identity-correction' => 'identity',
    'account-emails' => 'emails',
    'login-activity' || 'security' => 'sessions',
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
    final id = buyerLinkId(rawId);
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
    final id = buyerLinkId(rawId);
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
