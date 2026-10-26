import 'web_session.dart';

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
    await session.submit('/logout', {});
    session.clear();
  }

  Future<WebPage> registration() => session.page('/register');
  Future<void> validateRegistration(
    Map<String, dynamic> values, {
    int? step,
  }) async {
    await session.jsonPost('/register/validate', {
      ...values,
      'role': 'buyer',
      'step': ?step,
    });
  }

  Future<WebPage> register(Map<String, dynamic> values, String token) async {
    final page = await session.submit('/register', {
      ...values,
      'role': 'buyer',
      'otp_token': token,
    });
    requireNoErrors(page);
    return page;
  }

  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) => session.jsonPost(resend ? '/otp/resend' : '/otp/send', {
    'email': email.trim().toLowerCase(),
    'purpose': purpose,
    'role': 'buyer',
  });
  Future<String> verifyCode(String email, String purpose, String code) async {
    final data = await session.jsonPost('/otp/verify', {
      'email': email.trim().toLowerCase(),
      'purpose': purpose,
      'code': code,
      'role': 'buyer',
    });
    final token = data['token'];
    if (token is! String || token.isEmpty) {
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
    await session.jsonPost('/password/reset-otp', {
      'email': email.trim().toLowerCase(),
      'role': 'buyer',
      'token': token,
      'password': password,
      'password_confirmation': confirmation,
    });
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
