import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'core/buyer_repository.dart';
import 'core/buyer_actions.dart';
import 'core/web_session.dart';
import 'core/widgets.dart';
import 'features/auth/login_page.dart';
import 'features/auth/google_buyer_registration_page.dart';
import 'features/auth/native_google_sign_in.dart';
import 'features/auth/recovery_page.dart';
import 'features/auth/register_page.dart';
import 'features/home/home_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/notifications/push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotifications.instance.initialize();
  runApp(const MainApp());
}

enum _Screen { login, registration, googleRegistration, recovery, home }

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.repository});
  final BuyerRepository? repository;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _navigator = GlobalKey<NavigatorState>();
  String? _pendingProduct;
  int _pendingDestination = 0;
  BuyerRepository? _repository;
  String? _configurationError;
  _Screen _screen = _Screen.login;
  WebPage? _initial;
  GoogleRegistrationChallenge? _googleChallenge;
  String? _pendingNotificationId;
  String? _notice;
  @override
  void initState() {
    super.initState();
    PushNotifications.instance.openedNotificationId.addListener(
      _handlePushOpen,
    );
    _handlePushOpen();
    if (widget.repository != null) {
      _repository = widget.repository;
      return;
    }
    const configured = String.fromEnvironment('BAGOO_BASE_URL');
    final source = configured.isNotEmpty
        ? configured
        : kDebugMode
        ? (Platform.isAndroid
              ? 'http://10.0.2.2:8000'
              : 'http://localhost:8000')
        : '';
    try {
      final origin = Uri.parse(source);
      if (kReleaseMode && origin.scheme != 'https') {
        throw ArgumentError('HTTPS is required for release builds.');
      }
      _repository = BuyerRepository(WebSession(origin));
    } on ArgumentError {
      _configurationError =
          'The BagooPH service is not configured for this build.';
    } on FormatException {
      _configurationError = 'The BagooPH service configuration is invalid.';
    }
  }

  void _go(_Screen screen, {String? notice}) {
    setState(() {
      _screen = screen;
      _notice = notice;
    });
  }

  void _authenticated(WebPage page) {
    setState(() {
      _initial = page;
      _screen = _Screen.home;
      _googleChallenge = null;
      _notice = null;
    });
    final userId = page.user?['id'];
    if (userId is num) {
      unawaited(
        PushNotifications.instance.syncIfAuthorized(
          _repository!,
          userId.toInt(),
        ),
      );
    }
    _openPendingNotification();
  }

  void _handlePushOpen() {
    final id = PushNotifications.instance.openedNotificationId.value;
    if (id == null) return;
    PushNotifications.instance.openedNotificationId.value = null;
    _pendingNotificationId = id;
    if (_screen == _Screen.login && mounted) {
      setState(() => _notice = 'Sign in to view this Bagoo update.');
    }
    _openPendingNotification();
  }

  void _openPendingNotification() {
    final id = _pendingNotificationId;
    final user = _initial?.user;
    final userId = user?['id'];
    if (id == null ||
        _screen != _Screen.home ||
        user?['role'] != 'buyer' ||
        userId is! num) {
      return;
    }
    _pendingNotificationId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _repository == null) return;
      _navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsPage(
            repository: _repository!,
            ownerId: userId.toInt(),
            initialNotificationId: id,
          ),
        ),
      );
    });
  }

  Future<void> _logout() async {
    await PushNotifications.instance.unregister(_repository!);
    await _repository!.logout();
    await NativeGoogleSignIn.instance.signOut();
    if (mounted) {
      setState(() {
        _initial = null;
        _pendingDestination = 0;
        _pendingProduct = null;
        _pendingNotificationId = null;
        _screen = _Screen.login;
        _notice = 'You have been logged out.';
      });
    }
  }

  @override
  void dispose() {
    PushNotifications.instance.openedNotificationId.removeListener(
      _handlePushOpen,
    );
    if (widget.repository == null) {
      _repository?.session.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BagooPH Buyer',
    navigatorKey: _navigator,
    builder: (context, child) => BuyerActions(
      signIn: (slug) {
        _pendingProduct = slug;
        _pendingDestination = 0;
        _navigator.currentState?.popUntil((route) => route.isFirst);
        _go(_Screen.login);
      },
      signInTo: (destination) {
        _pendingDestination = destination == 'profile'
            ? 3
            : destination == 'cart'
            ? 1
            : destination == 'search'
            ? 2
            : 0;
        _pendingProduct = null;
        _navigator.currentState?.popUntil((route) => route.isFirst);
        _go(_Screen.login);
      },
      child: child ?? const SizedBox.shrink(),
    ),
    debugShowCheckedModeBanner: false,
    theme: BagooTheme.light,
    themeMode: ThemeMode.light,
    home: _repository == null
        ? Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Notice(_configurationError!, error: true),
                ),
              ),
            ),
          )
        : PopScope(
            canPop: _screen == _Screen.login || _screen == _Screen.home,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                _go(_Screen.login);
              }
            },
            child: switch (_screen) {
              _Screen.login => LoginPage(
                repository: _repository!,
                notice: _notice,
                onAuthenticated: _authenticated,
                onGoogleRegistration: (challenge) => setState(() {
                  _googleChallenge = challenge;
                  _screen = _Screen.googleRegistration;
                  _notice = null;
                }),
                onRegister: () => _go(_Screen.registration),
                onForgot: () => _go(_Screen.recovery),
                onBrowse: () {
                  _initial = null;
                  _pendingDestination = 0;
                  _go(_Screen.home);
                },
              ),
              _Screen.registration => RegisterPage(
                repository: _repository!,
                onBack: () => _go(_Screen.login),
                onBrowse: () {
                  _initial = null;
                  _pendingDestination = 0;
                  _go(_Screen.home);
                },
                onComplete: (page) {
                  if (page.user != null) {
                    _authenticated(page);
                  } else {
                    _go(
                      _Screen.login,
                      notice:
                          page.props['status']?.toString() ??
                          'Your account was created. Please log in.',
                    );
                  }
                },
              ),
              _Screen.googleRegistration => GoogleBuyerRegistrationPage(
                repository: _repository!,
                challenge: _googleChallenge!,
                onBack: () {
                  _googleChallenge = null;
                  _go(_Screen.login);
                },
                onBrowse: () {
                  _googleChallenge = null;
                  _initial = null;
                  _go(_Screen.home);
                },
                onComplete: _authenticated,
              ),
              _Screen.recovery => RecoveryPage(
                repository: _repository!,
                onBack: () => _go(_Screen.login),
                onBrowse: () {
                  _initial = null;
                  _pendingDestination = 0;
                  _go(_Screen.home);
                },
                onComplete: () => _go(
                  _Screen.login,
                  notice: 'Password reset successfully. Please log in with your new password.',
                ),
              ),
              _Screen.home => HomePage(
                repository: _repository!,
                initial: _initial,
                initialProductSlug: _pendingProduct,
                initialDestination: _pendingDestination,
                onDestinationRestored: () => _pendingDestination = 0,
                onProductRestored: () => _pendingProduct = null,
                onLogin: () => _go(_Screen.login),
                onLogout: _logout,
              ),
            },
          ),
  );
}
