import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import 'app/theme.dart';
import 'core/buyer_repository.dart';
import 'core/buyer_actions.dart';
import 'core/web_session.dart';
import 'core/widgets.dart';
import 'core/native_session_vault.dart';
import 'core/catalogue_cache.dart';
import 'features/auth/login_page.dart';
import 'features/auth/google_identity.dart';
import 'features/auth/recovery_page.dart';
import 'features/auth/register_page.dart';
import 'features/home/home_page.dart';
import 'features/home/search_controller.dart';
import 'features/home/search_page.dart';
import 'features/profile/profile_page.dart';
import 'features/engagement/buyer_link.dart';
import 'features/engagement/buyer_destination_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

enum _Screen { login, registration, recovery, home }

class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    this.repository,
    this.incomingLinks,
    this.googleProvider,
  });
  final BuyerRepository? repository;
  final Stream<Uri>? incomingLinks;
  final GoogleIdentityProvider? googleProvider;
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
  bool _providerFlowActive = false;
  int _probeGeneration = 0;
  StreamSubscription<Uri>? _links;
  BuyerLink? _pendingLink;
  int _linkGeneration = 0;
  int? _resolvingLink;
  late final _BuyerNavigationObserver _routes;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _routes = _BuyerNavigationObserver(() => _scheduleLink());
    if (widget.repository != null) {
      _repository = widget.repository;
      _bindLinks();
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
        catalogueCache: CatalogueCache(
          origin: origin,
          vault: const NativeSessionVault(),
        ),
      );
      _restoring = true;
      _bindLinks();
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
    if (mounted) _scheduleLink();
  }

  void _bindLinks() {
    final stream =
        widget.incomingLinks ??
        (widget.repository == null ? AppLinks().uriLinkStream : null);
    _links = stream?.listen((uri) {
      try {
        final link = BuyerLink.parse(uri, _repository!.session.origin);
        _pendingLink = link;
        _linkGeneration++;
        _scheduleLink();
      } on BackendException catch (e) {
        _linkMessage(e.message);
      } on FormatException {
        _linkMessage('This buyer link is invalid.');
      }
    }, onError: (_) => _linkMessage('This buyer link could not be opened.'));
  }

  void _linkMessage(String message) {
    final context = _navigator.currentState?.overlay?.context;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else if (mounted) {
      setState(() => _notice = message);
    }
  }

  void _scheduleLink() {
    if (!mounted || _pendingLink == null || _restoring || _providerFlowActive) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openPendingLink());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openPendingLink() async {
    final link = _pendingLink;
    final generation = _linkGeneration;
    final context = _navigator.currentState?.overlay?.context;
    if (link == null ||
        context == null ||
        !mounted ||
        _providerFlowActive ||
        _resolvingLink == generation ||
        _restoring) {
      return;
    }
    if (_routes.blocksLink) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'A buyer link is ready. Finish the current action before opening it.',
          ),
          action: SnackBarAction(label: 'Open', onPressed: _scheduleLink),
        ),
      );
      return;
    }
    _resolvingLink = generation;
    try {
      Map<String, dynamic>? user = _initial?.user;
      if (link.requiresLogin) {
        final page = await _repository!.currentSession();
        if (!mounted || generation != _linkGeneration) return;
        if (page == null) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
          _initial = null;
          _go(_Screen.login, notice: 'Sign in to open this buyer link.');
          return;
        }
        user = page.user;
      }
      if (!mounted || generation != _linkGeneration || !context.mounted) return;
      _pendingLink = null;
      await BuyerDestinationRouter.openHref(
        context,
        _repository!,
        link.uri.toString(),
        onSearch: (filters) => _openLinkedSearch(filters),
        onProfileSection: (section) => _openLinkedProfile(section, user),
      );
    } on BackendException catch (e) {
      if (mounted && generation == _linkGeneration) _linkMessage(e.message);
    } finally {
      if (_resolvingLink == generation) _resolvingLink = null;
    }
  }

  void _openLinkedSearch(SearchFilters filters) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Search Bagoo')),
          body: SearchPage(repository: _repository!, request: filters),
        ),
      ),
    );
  }

  void _openLinkedProfile(String section, Map<String, dynamic>? user) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Buyer account')),
          body: ProfilePage(
            repository: _repository!,
            user: user,
            initialSection: section,
            onLogin: () {
              _navigator.currentState?.popUntil((route) => route.isFirst);
              _go(_Screen.login);
            },
            onLogout: _logout,
            onUserChanged: (_) {},
            onSearch: _openLinkedSearch,
          ),
        ),
      ),
    );
  }

  void _sessionEnded() {
    _probeGeneration++;
    _linkGeneration++;
    _pendingLink = null;
    setState(() {
      _initial = null;
      _pendingProduct = null;
      _pendingDestination = 0;
      _screen = _Screen.login;
      _notice = 'You have been logged out.';
    });
  }

  Future<void> _probeSession() async {
    if (_providerFlowActive) return;
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

  void _providerFlowChanged(bool active) {
    if (!mounted) return;
    _providerFlowActive = active;
    _probeGeneration++;
    if (active) _linkGeneration++;
    if (!active) {
      _scheduleLink();
      if (_screen != _Screen.home) unawaited(_probeSession());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _repository != null &&
        _screen != _Screen.home) {
      unawaited(_probeSession());
    }
    if (state == AppLifecycleState.resumed) _scheduleLink();
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
    _linkGeneration++;
    _scheduleLink();
  }

  Future<void> _logout() async {
    await _repository!.logout();
    if (mounted) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
      _sessionEnded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _probeGeneration++;
    _linkGeneration++;
    unawaited(_links?.cancel());
    _pendingLink = null;
    if (widget.repository == null) {
      _repository?.session.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BagooPH Buyer',
    navigatorKey: _navigator,
    navigatorObservers: [_routes],
    builder: (context, child) => BuyerActions(
      sessionEnded: _sessionEnded,
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
                googleProvider: widget.googleProvider,
                onProviderFlowChanged: _providerFlowChanged,
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

class _BuyerNavigationObserver extends NavigatorObserver {
  _BuyerNavigationObserver(this.changed);
  final VoidCallback changed;
  final _routes = <Route<dynamic>>[];
  bool get blocksLink =>
      _routes.isNotEmpty &&
      !_routes.last.isFirst &&
      _routes.last.popDisposition == RoutePopDisposition.doNotPop;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    changed();
  }
}
