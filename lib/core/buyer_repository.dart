import 'web_session.dart';
import 'uploads.dart';

class BuyerRepository {
  BuyerRepository(this.session);
  final WebSession session;

  Future<WebPage> login(String email, String password) async {
    final page = await session.submit('/login', {
      'email': email.trim().toLowerCase(),
      'password': password,
      'role': 'buyer',
      'remember': false,
    });
    requireNoErrors(page);
    if (page.user == null || page.user?['role'] != 'buyer') {
      throw const BackendException(
        'We could not sign in to your buyer account. Please try again.',
      );
    }
    return page;
  }

  Future<void> logout() async {
    final page = await session.submit('/logout', {});
    requireNoErrors(page);
    if (page.user != null) {
      throw const BackendException(
        'We could not confirm logout. Please try again.',
      );
    }
    session.clear();
  }

  Future<WebPage> registration() => session.page('/register');
  Future<void> validateRegistration(
    Map<String, dynamic> values, {
    int? step,
  }) async {
    final data = await session.jsonPost('/register/validate', {
      ...values,
      'role': 'buyer',
      'step': ?step,
    });
    _requireConfirmation(data, 'valid');
  }

  Future<WebPage> register(Map<String, dynamic> values, String token) async {
    final page = await session.submit('/register', {
      ...values,
      'role': 'buyer',
      'otp_token': token,
    });
    requireNoErrors(page);
    final status = page.props['status'];
    if (page.user == null && (status is! String || status.isEmpty)) {
      throw const BackendException(
        'We could not confirm account creation. Try logging in before submitting again.',
      );
    }
    return page;
  }

  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    final data = await session.jsonPost(resend ? '/otp/resend' : '/otp/send', {
      'email': email.trim().toLowerCase(),
      'purpose': purpose,
      'role': 'buyer',
    });
    _requireConfirmation(data, 'success');
    return data;
  }

  Future<String> verifyCode(String email, String purpose, String code) async {
    final data = await session.jsonPost('/otp/verify', {
      'email': email.trim().toLowerCase(),
      'purpose': purpose,
      'code': code,
      'role': 'buyer',
    });
    final token = data['token'];
    if (data['success'] != true || token is! String || token.isEmpty) {
      throw const BackendException(
        'Verification did not finish. Please request a new code.',
      );
    }
    return token;
  }

  Future<void> resetPassword(
    String email,
    String token,
    String password,
    String confirmation,
  ) async {
    final data = await session.jsonPost('/password/reset-otp', {
      'email': email.trim().toLowerCase(),
      'role': 'buyer',
      'token': token,
      'password': password,
      'password_confirmation': confirmation,
    });
    _requireConfirmation(data, 'success');
  }

  void _requireConfirmation(Map<String, dynamic> data, String field) {
    if (data[field] != true) {
      throw const BackendException(
        'BagooPH did not confirm this request. Please try again.',
      );
    }
  }

  Future<WebPage> home({
    String search = '',
    String category = '',
    String sort = 'relevance',
    int page = 1,
  }) async {
    final query = Uri(
      queryParameters: {
        if (search.isNotEmpty) 'search': search,
        if (category.isNotEmpty) 'category': category,
        if (sort != 'relevance') 'sort': sort,
        if (page > 1) 'page': '$page',
      },
    ).query;
    final result = await session.page('/${query.isNotEmpty ? '?$query' : ''}');
    requireNoErrors(result);
    return result;
  }

  Future<WebPage> product(String slug) async {
    final result = await session.page(
      '/buyer/product/${Uri.encodeComponent(slug)}',
    );
    requireNoErrors(result);
    if (result.component != 'Buyer/ProductDetail' ||
        result.props['product'] is! Map) {
      throw const BackendException('This product is not available.');
    }
    return result;
  }

  Future<WebPage> search(Map<String, String> filters, {int page = 1}) async {
    final query = Uri(
      queryParameters: {...filters, if (page > 1) 'page': '$page'},
    ).query;
    final result = await session.page(
      '/buyer/search${query.isEmpty ? '' : '?$query'}',
    );
    requireNoErrors(result);
    if (result.component != 'Buyer/Search' ||
        result.props['products'] is! Map) {
      throw const BackendException('Product search is unavailable. Try again.');
    }
    return result;
  }

  Future<bool> saveProduct(int id, bool saved) async {
    final data = await session.jsonPost(
      '/buyer/saved-products/$id',
      {},
      method: saved ? 'POST' : 'DELETE',
    );
    if (data['product_id'] != id || data['saved'] != saved) {
      throw const BackendException(
        'The saved product change was not confirmed.',
      );
    }
    return saved;
  }

  Future<WebPage> addToBag(
    Map<String, dynamic> product,
    int quantity, {
    String? color,
    String? size,
    bool buyNow = false,
    int previousQuantity = 0,
  }) async {
    final page = await session.submit(
      '/cart',
      {
        'product_id': product['id'],
        'quantity': quantity,
        'color': color,
        'size': size,
        'buy_now': buyNow,
      },
      referer:
          '/buyer/product/${Uri.encodeComponent(product['slug'].toString())}',
    );
    requireNoErrors(page);
    if (buyNow) {
      if (page.component != 'Checkout/Index' ||
          page.props['checkoutToken'] is! String ||
          (page.props['checkoutToken'] as String).isEmpty) {
        throw const BackendException(
          'Sign in with an approved buyer account before checkout.',
        );
      }
    } else {
      final rows = mapsOf(page.props['cartQuantities']);
      final line = rows
          .where((row) => row['color'] == color && row['size'] == size)
          .firstOrNull;
      if (line == null ||
          (num.tryParse(line['quantity'].toString()) ?? 0) <
              previousQuantity + quantity) {
        throw const BackendException(
          'The Bag change could not be confirmed. Refresh before trying again.',
        );
      }
    }
    return page;
  }

  Future<WebPage> bag() async {
    final page = await session.page('/cart');
    requireNoErrors(page);
    if (page.component != 'Cart/Index') {
      throw const BackendException(
        'Your Shopping Bag is unavailable for this account.',
      );
    }
    return page;
  }

  Future<Map<String, dynamic>> bagQuote(List<int> ids) => session.jsonGet(
    '/cart?${Uri(queryParameters: {'item_ids[]': ids.map((id) => '$id').toList()}).query}',
  );

  Future<WebPage> changeBagItem(int id, int? quantity) async {
    final page = await session.submit(
      '/cart/$id',
      quantity == null ? {} : {'quantity': quantity},
      method: quantity == null ? 'DELETE' : 'PATCH',
      referer: '/cart',
    );
    requireNoErrors(page);
    if (page.component != 'Cart/Index') {
      throw const BackendException('Your Bag update was not confirmed.');
    }
    final item = mapsOf(page.props['items'])
        .where((i) => i['id'] == id)
        .firstOrNull;
    if (quantity == null ? item != null : item?['quantity'] != quantity) {
      throw const BackendException(
        'Your Bag update was not confirmed. Refresh before retrying.',
      );
    }
    return page;
  }

  Future<WebPage> checkout(List<int> ids) async {
    final page = await session.page('/checkout?items=${ids.join(',')}');
    requireNoErrors(page);
    if (page.component != 'Checkout/Index') {
      throw const BackendException(
        'Checkout requires an active approved buyer account and available items.',
      );
    }
    return page;
  }

  Future<Map<String, dynamic>> quote(Map<String, dynamic> values) =>
      session.jsonPost('/buyer/vouchers/apply', values);
  Future<Map<String, dynamic>> voucherChoices(
    Map<String, dynamic> values,
  ) async {
    final result = await session.jsonPost('/buyer/vouchers/choices', values);
    if (mapOf(result['offers'])['data'] is! List) {
      throw const BackendException(
        'Voucher choices could not load. Try again.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> bestVouchers(Map<String, dynamic> values) async {
    final result = await session.jsonPost('/buyer/vouchers/best', values);
    if (result['selection'] is! Map || result['quote'] is! Map) {
      throw const BackendException(
        'Voucher comparison was not confirmed. Try again.',
      );
    }
    return result;
  }

  Future<WebPage> placeOrder(Map<String, dynamic> values) async {
    final page = await session.submit(
      '/checkout',
      values,
      referer: '/checkout',
    );
    requireNoErrors(page);
    final success = mapOf(page.props['flash'])['success'];
    if (success is! String ||
        success.trim().isEmpty ||
        ![
          'Buyer/Orders',
          'Buyer/WalletPayment',
          'Buyer/Profile',
        ].contains(page.component)) {
      throw const BackendException(
        'Order placement was not confirmed. Keep these checkout details and check your orders before retrying.',
      );
    }
    return page;
  }

  Future<WebPage> shop(
    String slug, {
    int page = 1,
    String search = '',
    String category = '',
    String storeCategory = 'all',
    String sort = 'relevance',
  }) async {
    final query = Uri(
      queryParameters: {
        'page': '$page',
        if (search.isNotEmpty) 'search': search,
        if (category.isNotEmpty) 'category': category,
        if (storeCategory != 'all') 'store_category': storeCategory,
        if (sort != 'relevance') 'sort': sort,
      },
    ).query;
    final data = await session.page(
      '/shop/${Uri.encodeComponent(slug)}?$query',
    );
    requireNoErrors(data);
    if (data.component != 'Marketplace/ShopDetail') {
      throw const BackendException('This shop is not available.');
    }
    return data;
  }

  Future<WebPage> reminder(String slug, int id, bool subscribed) async {
    final data = await session.submit(
      '/buyer/sale-reminders/$id',
      {},
      method: subscribed ? 'POST' : 'DELETE',
      referer: '/buyer/product/${Uri.encodeComponent(slug)}',
    );
    requireNoErrors(data);
    if (mapOf(data.props['saleReminder'])['subscribed'] != subscribed) {
      throw const BackendException('The reminder change was not confirmed.');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> messages(int receiver) async {
    final data = await session.jsonGet('/chat/messages/$receiver');
    if (data['messages'] is! List) {
      throw const BackendException('Conversation unavailable.');
    }
    return mapsOf(data['messages']);
  }

  Future<Map<String, dynamic>> sendMessage(
    Map<String, dynamic> values, {
    List<UploadPart>? files,
  }) async {
    final data = files != null && files.isNotEmpty
        ? await session.uploadJson('/chat/send', values, files)
        : await session.jsonPost('/chat/send', values);
    if (data['success'] != true || mapOf(data['message'])['id'] is! num) {
      throw const BackendException('Your message was not confirmed.');
    }
    return mapOf(data['message']);
  }

  Future<WebPage> document(String path) => session.page(path);

  void requireNoErrors(WebPage page) {
    if (page.errors.isNotEmpty) {
      throw BackendException(
        'Please check the highlighted fields.',
        fields: page.errors,
      );
    }
    final error = mapOf(page.props['flash'])['error'];
    if (error is String && error.isNotEmpty) {
      throw BackendException(error);
    }
  }
}
