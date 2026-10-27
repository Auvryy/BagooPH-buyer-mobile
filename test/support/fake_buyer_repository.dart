import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';

const buyer = {
  'id': 7,
  'name': 'Test Buyer',
  'email': 'buyer@example.test',
  'role': 'buyer',
  'status': 'active',
  'kyc_status': 'approved',
};
Map<String, dynamic> product(int id) => {
  'id': id,
  'slug': 'everyday-bag-$id',
  'name': 'Everyday bag $id',
  'price': '1200.00',
  'stock': 4,
  'rating': null,
  'sales_count': 0,
  'shop': {'name': 'Test store', 'city': 'Test city'},
};
WebPage homePage({
  bool signedIn = false,
  int page = 1,
  int lastPage = 1,
  List<Map<String, dynamic>>? products,
}) => WebPage('Buyer/Home', {
  'auth': {'user': signedIn ? buyer : null},
  'errors': {},
  'categories': [
    {'id': 2, 'name': 'Electronics and Gadgets', 'slug': 'electronics'},
  ],
  'banners': [],
  'feedProducts': {
    'data': products ?? [product(1), product(2)],
    'current_page': page,
    'last_page': lastPage,
    'total': 4,
  },
});

class FakeBuyerRepository extends BuyerRepository {
  FakeBuyerRepository() : super(FakeSession());
  bool signedIn = false;
  int loginCalls = 0;
  int registerCalls = 0;
  int sendCalls = 0;
  int resetCalls = 0;
  int validationCalls = 0;
  BackendException? loginError;
  final homeRequests = <Map<String, dynamic>>[];
  final searchRequests = <Map<String, String>>[];
  Future<WebPage> Function(String search, int page)? homeHandler;
  int productCalls = 0;
  int bagCalls = 0;
  int saveCalls = 0;
  int orderCalls = 0;
  Map<String, dynamic>? submittedOrder;
  Future<WebPage> Function(Map<String, dynamic>)? orderHandler;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? quoteHandler;
  BackendException? productError;
  WebPage? productResponse;
  final savedIds = <int>{};
  @override
  Future<WebPage> search(Map<String, String> filters, {int page = 1}) async {
    searchRequests.add({...filters, 'page': '$page'});
    final home = homePage(signedIn: signedIn, page: page);
    return WebPage('Buyer/Search', {
      ...home.props,
      'products': home.props['feedProducts'],
      'locations': <Map<String, dynamic>>[],
      'relatedProducts': [],
      'suggestions': [],
    });
  }

  @override
  Future<WebPage> product(String slug) async {
    productCalls++;
    if (productError != null) {
      throw productError!;
    }
    return productResponse ?? productPage(signedIn: signedIn);
  }

  @override
  Future<bool> saveProduct(int id, bool saved) async {
    saveCalls++;
    saved ? savedIds.add(id) : savedIds.remove(id);
    return saved;
  }

  @override
  Future<WebPage> bag() async {
    bagCalls++;
    return WebPage('Cart/Index', {
      'auth': {'user': signedIn ? buyer : null},
      'items': [],
    });
  }

  @override
  Future<WebPage> addToBag(
    Map<String, dynamic> product,
    int quantity, {
    String? color,
    String? size,
    bool buyNow = false,
    int previousQuantity = 0,
  }) async {
    if (buyNow) {
      return checkoutPage();
    }
    final page = productPage(signedIn: signedIn);
    page.props['cartQuantities'] = [
      {'color': color, 'size': size, 'quantity': previousQuantity + quantity},
    ];
    return page;
  }

  @override
  Future<Map<String, dynamic>> quote(Map<String, dynamic> values) async =>
      quoteHandler != null
      ? quoteHandler!(values)
      : {
          'success': true,
          'quote': checkoutPage().props['quote'],
          'availableVouchers': [],
        };
  @override
  Future<WebPage> placeOrder(Map<String, dynamic> values) async {
    orderCalls++;
    submittedOrder = values;
    if (orderHandler != null) return orderHandler!(values);
    return const WebPage('Buyer/Profile', {
      'flash': {'success': 'Order #TEST-1 successfully placed.'},
      'orders': {'data': []},
    });
  }

  @override
  Future<WebPage> login(String email, String password) async {
    loginCalls++;
    if (loginError != null) {
      throw loginError!;
    }
    signedIn = true;
    return homePage(signedIn: true);
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<WebPage> home({
    String search = '',
    String category = '',
    String sort = 'relevance',
    int page = 1,
  }) async {
    homeRequests.add({
      'search': search,
      'category': category,
      'sort': sort,
      'page': page,
    });
    return homeHandler != null
        ? homeHandler!(search, page)
        : homePage(signedIn: signedIn);
  }

  @override
  Future<WebPage> registration() async => const WebPage('Auth/Register', {
    'birthDateLimits': {'adult_maximum': '2008-10-26', 'today': '2026-10-26'},
    'policies': {
      'terms_version': '2026-10-12',
      'privacy_version': '2026-10-12',
      'terms_url': '/terms/2026-10-12',
      'privacy_url': '/privacy/2026-10-12',
    },
  });
  @override
  Future<void> validateRegistration(
    Map<String, dynamic> values, {
    int? step,
  }) async {
    validationCalls++;
  }

  @override
  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    sendCalls++;
    return {'success': true, 'cooldown': 0};
  }

  @override
  Future<String> verifyCode(String email, String purpose, String code) async {
    if (code != '123456') {
      throw const BackendException('Incorrect code.');
    }
    return 'test-verification-token';
  }

  @override
  Future<WebPage> register(Map<String, dynamic> values, String token) async {
    registerCalls++;
    signedIn = true;
    return homePage(signedIn: true);
  }

  @override
  Future<void> resetPassword(
    String email,
    String token,
    String password,
    String confirmation,
  ) async {
    resetCalls++;
  }
}

WebPage productPage({bool signedIn = false, Map<String, dynamic>? override}) =>
    WebPage('Buyer/ProductDetail', {
      'auth': {'user': signedIn ? buyer : null},
      'product': {
        ...product(1),
        'sku': 'BAG-001',
        'compare_at_price': '1500.00',
        'description': 'Everyday essentials with a durable finish.',
        'category': {'name': 'Travel and Accessories'},
        'brand': 'Bagoo',
        'condition': 'new',
        'weight_kg': '1.1',
        'images': [],
        'reviews': [],
        'shop': {
          'id': 2,
          'user_id': 3,
          'name': 'Test store',
          'slug': 'test-store',
          'city': 'Test city',
          'status': 'active',
        },
        ...?override,
      },
      'variations': {'colors': [], 'sizes': []},
      'cartQuantities': [],
      'savedProductIds': [],
      'shopStats': {
        'rating': 4.5,
        'products_count': 5,
        'response_rate': '50%',
        'joined': '2026-10-01',
      },
      'relatedProducts': [],
      'shopOffers': [],
    });
WebPage checkoutPage() => const WebPage('Checkout/Index', {
  'checkoutToken': 'test-checkout-token',
  'auth': {'user': buyer},
  'user': buyer,
  'items': [
    {
      'id': 1,
      'quantity': 1,
      'unit_price': '1200.00',
      'product': {'name': 'Everyday bag 1'},
    },
  ],
  'itemQuantities': {},
  'quote': {
    'subtotal': 1200.0,
    'shipping_fee': 50.0,
    'doorstep_shipping_fee': 50.0,
    'discount': 0.0,
    'shipping_discount': 0.0,
    'total': 1250.0,
    'shops': [
      {
        'shop_id': 2,
        'shop_name': 'Test store',
        'subtotal': 1200.0,
        'shipping': 50.0,
        'discount': 0.0,
        'product_discount': 0.0,
        'shipping_discount': 0.0,
        'total': 1250.0,
      },
    ],
    'items': [
      {
        'id': 1,
        'price_segments': [
          {'quantity': 1, 'unit_price': 1200.0, 'subtotal': 1200.0},
        ],
      },
    ],
  },
  'availableVouchers': [],
  'addresses': [
    {
      'id': 1,
      'recipient_name': 'Test Buyer',
      'phone': '09171234567',
      'street': '123 Test Street',
      'province': 'Laguna',
      'city': 'San Pablo City',
      'barangay': 'San Rafael',
      'postal_code': '4000',
      'region': '0400000000',
      'is_default': true,
    },
  ],
  'defaultAddressId': 1,
  'pickupHubs': [],
  'walletBalanceCents': 200000,
});

class FakeSession extends WebSession {
  FakeSession() : super(Uri.parse('http://backend.test'));
  WebPage? profileResponse;
  @override
  Future<WebPage> page(String path, {bool bootstrap = false}) async {
    if (path.startsWith('/buyer/profile')) {
      return profileResponse ??
          const WebPage('Buyer/Profile', {
            'auth': {'user': buyer},
            'user': buyer,
            'canUsePortal': true,
            'addresses': [],
            'orders': {'data': [], 'current_page': 1, 'last_page': 1},
            'orderCounts': {},
            'ordersCount': 0,
          });
    }
    throw StateError('No isolated page fixture for $path');
  }

  @override
  Future<Map<String, dynamic>> jsonGet(String path) async {
    if (path.startsWith('/address-locations')) {
      return {
        'regions': [
          {'value': '0400000000', 'label': 'CALABARZON'},
        ],
        'provinces': [
          {'value': 'Laguna', 'label': 'Laguna'},
        ],
        'cities': [
          {'value': 'San Pablo City', 'label': 'San Pablo City'},
        ],
        'barangays': [
          {'value': 'San Rafael', 'label': 'San Rafael'},
        ],
        'resolved': {
          'region': '0400000000',
          'province': 'Laguna',
          'city': 'San Pablo City',
        },
      };
    }
    return {};
  }
}
