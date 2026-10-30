import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/addresses_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/email_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/identity_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/personal_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/sessions_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/wallet_section.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../test/support/account_fixtures.dart';
import '../test/support/address_fixtures.dart';
import '../test/support/no_network.dart';
import '../test/support/return_fixtures.dart';
import 'preview/buyer_device_preview.dart';

void main() {
  if (!kDebugMode || !Platform.isLinux) {
    throw UnsupportedError('The isolated account review requires debug Linux.');
  }
  HttpOverrides.global = NoNetworkHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AccountReview());
}

class _AccountReview extends StatefulWidget {
  const _AccountReview();
  @override
  State<_AccountReview> createState() => _AccountReviewState();
}

class _AccountReviewState extends State<_AccountReview> {
  static const screens = {
    'emails': 'Contact emails',
    'identity': 'Reviewed identity',
    'application': 'Rejected application',
    'sessions': 'Login sessions',
    'addresses': 'Delivery addresses',
    'personal': 'Personal details',
    'password': 'Password',
    'wallet': 'Demo wallet',
  };
  static const modes = {
    'ready': 'Successful response',
    'offline': 'Connection failure',
    'denied': 'Access denied',
    'conflict': 'Source conflict',
    'throttled': 'Code requests throttled',
  };
  String _screen = 'emails', _mode = 'ready';
  AccountFixtureRepository? _repository;
  late WebPage _page;
  int _revision = 0;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  Future<void> _response() async {
    final mode = _mode;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final status = switch (mode) {
      'offline' => 503,
      'denied' => 403,
      'conflict' => 409,
      'throttled' => 429,
      _ => null,
    };
    if (status != null) {
      throw BackendException(
        'Synthetic ${modes[mode]!.toLowerCase()}. Try again after reviewing the current details.',
        status: status,
        data: status == 429 ? {'cooldown': 900} : const {},
      );
    }
  }

  WebPage _copyPage() => WebPage(
    _page.component,
    Map<String, dynamic>.from(jsonDecode(jsonEncode(_page.props)) as Map),
  );

  void _reset() {
    _repository?.session.close();
    final repository = _repository = AccountFixtureRepository();
    void requireCurrentScene() {
      if (!mounted || !identical(_repository, repository)) {
        throw const BackendException(
          'The isolated QA screen was reset.',
          status: 401,
        );
      }
    }

    _page = switch (_screen) {
      'application' => applicationPage(),
      'addresses' => addressPage(),
      _ => accountPage(),
    };
    _revision++;
    _revoked = false;
    final session = repository.session as ReturnSession;
    session.onPage = (_) async {
      await _response();
      requireCurrentScene();
      return _copyPage();
    };
    session.onGet = (path) async {
      await _response();
      requireCurrentScene();
      if (path.startsWith('/address-locations')) {
        return addressLocationOptions();
      }
      final data = accountSessions();
      if (_revoked) {
        ((data['sessions'] as Map)['data'] as List).removeWhere(
          (row) => row['id'] == 'other-id',
        );
      }
      return data;
    };
    session.onDocument = (_) async {
      await _response();
      requireCurrentScene();
      return RemoteDocument(returnPhotoBytes(), 'image/png');
    };
    repository.onJson = (request) async {
      if (mounted) setState(() {});
      await _response();
      requireCurrentScene();
      if (request.path.endsWith('/send') || request.path.endsWith('/code')) {
        return {
          'success': true,
          'cooldown': 60,
          'message': 'Synthetic code request acknowledged. No email was sent.',
        };
      }
      if (request.path == '/account/identity-corrections') {
        final next = _copyPage();
        final subject =
            (next.props['identityCorrection'] as Map)['subject'] as Map;
        (subject['requests'] as List).add({
          'id': 1,
          'current': true,
          'requested_at': DateTime.now().toUtc().toIso8601String(),
          'reason': request.values['reason'],
          'before': subject['values'],
          'proposed': request.values['changes'],
          'documents': {},
          'decision': null,
        });
        _page = next;
        return {'id': 1};
      }
      if (request.path == '/wallet/credits') {
        final next = _copyPage();
        ((next.props['wallet'] as Map)['credit_requests'] as List).add({
          'reference': 'QA-CREDIT',
          'status': 'pending',
        });
        _page = next;
        return {'reference': 'QA-CREDIT', 'status': 'pending'};
      }
      if (request.path.contains('/account/security/sessions/')) {
        _revoked = true;
        return {
          'reference': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'affected_count': 1,
          'message': 'Synthetic session ended.',
        };
      }
      if (request.path.startsWith('/account/emails/')) {
        final next = _copyPage();
        final addresses =
            (next.props['emailSettings'] as Map)['addresses'] as List;
        if (request.path.endsWith('/confirm')) {
          addresses.add({
            'id': 3,
            'email': request.values['email'],
            'is_original': false,
            'verified': true,
            'preferred': false,
          });
        } else {
          final id = int.parse(request.path.split('/')[3]);
          if (request.method == 'DELETE') {
            addresses.removeWhere((row) => row['id'] == id);
          } else {
            for (final row in addresses) {
              row['preferred'] = row['id'] == id;
            }
          }
        }
        _page = next;
        return {'message': 'Synthetic email update saved.'};
      }
      throw StateError('Unsupported isolated account action: ${request.path}');
    };
    repository.onMutation = (request) async {
      if (mounted) setState(() {});
      await _response();
      requireCurrentScene();
      final next = _copyPage();
      if (request.path == '/buyer/profile') {
        (next.props['user'] as Map)['phone'] = request.values['phone'];
      } else if (request.path.startsWith('/buyer/addresses')) {
        final rows = mapsOf(next.props['addresses']);
        final id = int.tryParse(request.path.split('/').last);
        if (request.path.endsWith('/default')) {
          final selected = int.parse(request.path.split('/')[3]);
          for (final row in rows) {
            row['is_default'] = row['id'] == selected;
          }
        } else if (request.method == 'DELETE') {
          rows.removeWhere((row) => row['id'] == id);
        } else if (request.method == 'PATCH') {
          final row = rows.singleWhere((row) => row['id'] == id);
          final wasDefault = row['is_default'] == true;
          row.addAll(request.values);
          row['is_default'] = wasDefault || row['is_default'] == true;
          if (row['is_default'] == true) {
            for (final other in rows.where((other) => other['id'] != id)) {
              other['is_default'] = false;
            }
          }
        } else if (request.path == '/buyer/addresses' &&
            request.method == 'POST') {
          final nextId =
              rows.fold<int>(
                0,
                (max, row) => (row['id'] as int) > max ? row['id'] as int : max,
              ) +
              1;
          final isDefault =
              rows.isEmpty || request.values['is_default'] == true;
          if (isDefault) {
            for (final row in rows) {
              row['is_default'] = false;
            }
          }
          rows.add({...request.values, 'id': nextId, 'is_default': isDefault});
        } else {
          throw StateError('Unsupported isolated address action.');
        }
        next.props['addresses'] = rows;
      } else {
        throw StateError('Unsupported isolated profile action.');
      }
      next.props['flash'] = {'success': 'Synthetic profile update saved.'};
      _page = next;
      return next;
    };
  }

  Future<void> _reload() async {
    await _response();
    if (mounted) setState(() => _page = _copyPage());
  }

  Widget _section() {
    final repository = _repository!;
    void changed(WebPage page) => setState(() => _page = page);
    return switch (_screen) {
      'identity' || 'application' => IdentitySection(
        repository: repository,
        page: _page,
        onChanged: changed,
        reload: _reload,
      ),
      'sessions' => SessionsSection(repository: repository, owner: 7),
      'addresses' => AddressesSection(
        repository: repository,
        page: _page,
        onChanged: changed,
      ),
      'personal' => PersonalSection(
        repository: repository,
        page: _page,
        onChanged: changed,
        onIdentity: () => setState(() {
          _screen = 'identity';
          _reset();
        }),
      ),
      'password' => PasswordSection(
        repository: repository,
        page: _page,
        onChanged: changed,
      ),
      'wallet' => WalletSection(
        repository: repository,
        page: _page,
        reload: _reload,
        onPage: (_) {},
        onOrder: (_) {},
      ),
      _ => EmailSection(repository: repository, page: _page, reload: _reload),
    };
  }

  @override
  void dispose() {
    _repository?.session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Banner(
      message: 'ISOLATED QA',
      location: BannerLocation.topEnd,
      child: BuyerDevicePreview(
        extraControls: [
          const Divider(height: 36),
          DropdownButtonFormField<String>(
            initialValue: _screen,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'QA screen'),
            items: [
              for (final entry in screens.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _screen = value;
                  _mode = 'ready';
                  _reset();
                });
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_mode),
            initialValue: _mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Next response'),
            items: [
              for (final entry in modes.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _mode = value);
              }
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(_reset),
            child: const Text('Reset test screen'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _repository!.session.clear()),
            child: const Text('Change test account'),
          ),
          const SizedBox(height: 12),
          Text('Synthetic writes: ${_repository?.calls.length ?? 0}'),
          const SizedBox(height: 12),
          const Text(
            'Synthetic accounts and replies. Outbound requests are blocked. No real email, password, wallet or login session changes.',
          ),
        ],
        builder: (context) => MaterialApp(
          key: ValueKey((_screen, _revision)),
          debugShowCheckedModeBanner: false,
          theme: Theme.of(context),
          scrollBehavior: ScrollConfiguration.of(context),
          home: Scaffold(
            appBar: AppBar(title: Text(screens[_screen]!)),
            body: _section(),
          ),
        ),
      ),
    ),
  );
}
