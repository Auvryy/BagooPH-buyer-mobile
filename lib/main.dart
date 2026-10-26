import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'core/buyer_repository.dart';
import 'core/web_session.dart';
import 'core/widgets.dart';
import 'features/auth/login_page.dart';
import 'features/auth/recovery_page.dart';
import 'features/auth/register_page.dart';
import 'features/home/home_page.dart';

void main() {
  runApp(const MainApp());
}

enum _Screen { login, registration, recovery, home }

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.repository});
  final BuyerRepository? repository;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  BuyerRepository? _repository;
  String? _configurationError;
  _Screen _screen = _Screen.login;
  WebPage? _initial;
  String? _notice;
  @override
  void initState() {
    super.initState();
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
      _notice = null;
    });
  }

  Future<void> _logout() async {
    await _repository!.logout();
    if (mounted) {
      setState(() {
        _initial = null;
        _screen = _Screen.login;
        _notice = 'You have been logged out.';
      });
    }
  }

  @override
  void dispose() {
    if (widget.repository == null) {
      _repository?.session.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BagooPH Buyer',
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
                onRegister: () => _go(_Screen.registration),
                onForgot: () => _go(_Screen.recovery),
                onBrowse: () {
                  _initial = null;
                  _go(_Screen.home);
                },
              ),
              _Screen.registration => RegisterPage(
                repository: _repository!,
                onBack: () => _go(_Screen.login),
                onBrowse: () {
                  _initial = null;
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
                onLogin: () => _go(_Screen.login),
                onLogout: _logout,
              ),
            },
          ),
  );
}
