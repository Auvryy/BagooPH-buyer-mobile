import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'core/buyer_repository.dart';
import 'core/buyer_actions.dart';
import 'core/web_session.dart';
import 'core/widgets.dart';
import 'core/session_vault.dart';
import 'features/auth/login_page.dart';
import 'features/auth/recovery_page.dart';
import 'features/auth/register_page.dart';
import 'features/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

enum _Screen { login, registration, recovery, home }

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.repository});
  final BuyerRepository? repository;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  String? _pendingProduct;
  int _pendingDestination = 0;
  BuyerRepository? _repository;
  String? _configurationError;
  _Screen _screen = _Screen.login;
  WebPage? _initial;
  String? _notice;
  bool _restoring = false;
  int _probeGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.repository != null) {
      _repository = widget.repository;
      unawaited(_probeSession());
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
      _repository = BuyerRepository(
        WebSession(origin, vault: const NativeSessionVault()),
      );
      _restoring = true;
      unawaited(_restore());
    } on ArgumentError {
      _configurationError =
          'The BagooPH service is not configured for this build.';
    } on FormatException {
      _configurationError = 'The BagooPH service configuration is invalid.';
    }
  }

  Future<void> _restore() async {
    await _repository!.session.restoreSavedSession();
    if (mounted) await _probeSession();
  }

  Future<void> _probeSession() async {
    final generation = ++_probeGeneration;
    try {
      final page = await _repository!.currentSession();
      if (mounted &&
          generation == _probeGeneration &&
          _screen != _Screen.home &&
          page != null) {
        _authenticated(page);
      }
    } on BackendException catch (e) {
      if (mounted && generation == _probeGeneration) {
        setState(() => _notice = e.message);
      }
    } finally {
      if (mounted && generation == _probeGeneration) {
        setState(() => _restoring = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _repository != null &&
        _screen != _Screen.home) {
      unawaited(_probeSession());
    }
  }

  void _go(_Screen screen, {String? notice}) {
    _probeGeneration++;
    setState(() {
      _screen = screen;
      _notice = notice;
    });
    if (screen != _Screen.home) unawaited(_probeSession());
  }

  void _authenticated(WebPage page) {
    _probeGeneration++;
    setState(() {
      _initial = page;
      _screen = _Screen.home;
      _notice = null;
      _restoring = false;
    });
  }

  Future<void> _logout() async {
    await _repository!.logout();
    if (mounted) {
      _probeGeneration++;
      _navigator.currentState?.popUntil((route) => route.isFirst);
      setState(() {
        _initial = null;
        _pendingDestination = 0;
        _pendingProduct = null;
        _screen = _Screen.login;
        _notice = 'You have been logged out.';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _probeGeneration++;
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
        : _restoring
        ? const Scaffold(
            body: SafeArea(
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Checking saved session',
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
