import '../../core/web_session.dart';

enum BuyerLinkKind { destination, passwordReset, emailVerification }

int? buyerLinkId(String value) =>
    RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value) ? int.tryParse(value) : null;

class BuyerLink {
  const BuyerLink._(this.uri, this.kind, this.requiresLogin);
  final Uri uri;
  final BuyerLinkKind kind;
  final bool requiresLogin;

  static BuyerLink parse(Uri uri, Uri origin) {
    if (uri.toString().length > 4096 ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.origin != origin.origin ||
        uri.pathSegments.any(
          (part) =>
              part.contains('/') ||
              part.contains('\\') ||
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(part),
        )) {
      throw const BackendException('Use a buyer link for this Bagoo service.');
    }
    final parts = uri.pathSegments;
    if (parts.length == 2 &&
        parts.first == 'reset-password' &&
        RegExp(r'^[a-zA-Z0-9_-]{10,512}$').hasMatch(parts.last) &&
        (uri.queryParameters['role'] == null ||
            uri.queryParameters['role'] == 'buyer')) {
      return BuyerLink._(uri, BuyerLinkKind.passwordReset, false);
    }
    if (parts.length == 3 &&
        parts.first == 'verify-email' &&
        buyerLinkId(parts[1]) != null &&
        RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(parts[2]) &&
        RegExp(r'^[0-9]{1,11}$')
            .hasMatch(uri.queryParameters['expires'] ?? '') &&
        RegExp(r'^[a-fA-F0-9]{64}$')
            .hasMatch(uri.queryParameters['signature'] ?? '')) {
      return BuyerLink._(uri, BuyerLinkKind.emailVerification, true);
    }
    final public =
        parts.isEmpty ||
        parts.length == 1 && ['track', 'cart'].contains(parts.first) ||
        parts.length == 2 &&
            [
              'product',
              'shop',
              'promotions',
              'advertisement',
              'track',
            ].contains(parts.first) &&
            parts.last.isNotEmpty &&
            parts.last.length <= 200 ||
        parts.length == 2 && parts[0] == 'buyer' && parts[1] == 'search' ||
        parts.length == 3 &&
            parts[0] == 'buyer' &&
            parts[1] == 'product' &&
            parts.last.isNotEmpty &&
            parts.last.length <= 200 ||
        parts.length == 4 &&
            parts[0] == 'shop' &&
            parts[1].isNotEmpty &&
            parts[2] == 'categories' &&
            buyerLinkId(parts[3]) != null;
    if (public) return BuyerLink._(uri, BuyerLinkKind.destination, false);
    final private =
        parts.length == 1 &&
            [
              'notifications',
              'buyer-returns',
              'pending-approval',
              'verify-email',
              'checkout',
            ].contains(parts.first) ||
        parts.length == 2 &&
            parts.first == 'buyer' &&
            [
              'profile',
              'orders',
              'messages',
              'addresses',
              'saved-products',
              'followed-shops',
            ].contains(parts[1]) ||
        parts.length == 2 &&
            parts.first == 'account' &&
            ['status', 'settings', 'security'].contains(parts[1]) ||
        parts.length == 2 &&
            parts.first == 'buyer-returns' &&
            buyerLinkId(parts[1]) != null ||
        parts.length == 3 &&
            parts.first == 'buyer' &&
            parts[1] == 'orders' &&
            buyerLinkId(parts[2]) != null ||
        parts.length == 2 &&
            parts.first == 'wallet' &&
            parts[1] == 'payments' ||
        parts.length == 3 &&
            parts.first == 'wallet' &&
            parts[1] == 'payments' &&
            buyerLinkId(parts[2]) != null ||
        parts.length == 4 &&
            parts.first == 'buyer-returns' &&
            parts[1] == 'orders' &&
            buyerLinkId(parts[2]) != null &&
            parts[3] == 'create';
    if (private) return BuyerLink._(uri, BuyerLinkKind.destination, true);
    throw const BackendException(
      'This link has no supported native buyer destination.',
    );
  }
}
