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
  FakeBuyerRepository() : super(WebSession(Uri.parse('http://backend.test')));
  bool signedIn = false;
  int loginCalls = 0;
  int registerCalls = 0;
  int sendCalls = 0;
  int resetCalls = 0;
  int validationCalls = 0;
  BackendException? loginError;
  final homeRequests = <Map<String, dynamic>>[];
  Future<WebPage> Function(String search, int page)? homeHandler;
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
