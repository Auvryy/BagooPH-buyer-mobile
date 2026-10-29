import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_widgets.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../test/support/no_network.dart';
import '../test/support/return_fixtures.dart';
import 'preview/buyer_device_preview.dart';

void main() {
  if (!kDebugMode || !Platform.isLinux) {
    throw UnsupportedError('The isolated return review requires debug Linux.');
  }
  HttpOverrides.global = NoNetworkHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ReturnReview());
}

class _ReturnReview extends StatefulWidget {
  const _ReturnReview();
  @override
  State<_ReturnReview> createState() => _ReturnReviewState();
}

class _ReturnReviewState extends State<_ReturnReview> {
  static const screens = {
    'return-request': 'Request a return',
    'return-case': 'Return decisions',
    'private-image': 'Private image',
    'private-failure': 'Private document failure',
  };
  static const modes = {
    'ready': 'Successful response',
    'offline': 'Connection failure',
    'denied': 'Access denied',
    'long-error': 'Long failure feedback',
    'no-units': 'Purchased units already claimed',
    'new-reasons': 'Return reason choices changed',
  };
  String _screen = const String.fromEnvironment(
    'BAGOO_QA_SCREEN',
    defaultValue: 'return-request',
  );
  String _mode = 'ready';
  ReturnSession? _session;
  late ProfileRepository _repository;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    if (!screens.containsKey(_screen)) {
      throw ArgumentError('Choose a supported QA screen.');
    }
    if (_screen == 'private-failure') _mode = 'long-error';
    _reset();
  }

  void _reset() {
    _session?.close();
    final session = _session = ReturnSession();
    _repository = ProfileRepository(BuyerRepository(session));
    _revision++;
    session.onPage = (path) async {
      final mode = _mode;
      await _response(mode);
      if (path.endsWith('/create')) {
        final page = returnForm();
        if (mode == 'no-units') {
          ((page.props['items'] as List).first as Map)['available_quantity'] =
              0;
        }
        if (mode == 'new-reasons') {
          page.props['reasons'] = {'wrong_item': 'Wrong item'};
        }
        return page;
      }
      return returnDetail();
    };
    session.onSubmit = (request) async {
      await _response(_mode);
      return returnDetail(
        status: request.values['action'] == 'withdraw'
            ? 'withdrawn'
            : 'requested',
        version: 2,
        actions: [],
        success: 'Synthetic return update saved.',
      );
    };
    session.onDocument = (_) async {
      await _response(_mode);
      return RemoteDocument(returnPhotoBytes(), 'image/png');
    };
  }

  Future<void> _response(String mode) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mode == 'offline') {
      throw const BackendException(
        'The test connection is unavailable. Try again.',
        status: 503,
      );
    }
    if (mode == 'denied') {
      throw const BackendException(
        'Access to these private details has ended.',
        status: 403,
      );
    }
    if (mode == 'long-error') {
      throw BackendException(
        'The test document could not load. ${'Review your access and try again. ' * 16}',
        status: 503,
      );
    }
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Widget _content() => switch (_screen) {
    'return-request' => ReturnsPage(repository: _repository, orderId: 11),
    'return-case' => ReturnsPage(repository: _repository, caseId: 4),
    _ => PrivateDocumentPage(
      repository: _repository,
      path: '/buyer-returns/4/evidence/1',
      title: 'Private return evidence',
    ),
  };

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
              if (value == null) return;
              setState(() {
                _screen = value;
                _mode = value == 'private-failure' ? 'long-error' : 'ready';
                _reset();
              });
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('response-$_mode'),
            initialValue: _mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Next response'),
            items: [
              for (final entry in modes.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(_reset),
            child: const Text('Reset test screen'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _session!.clear()),
            child: const Text('Change test account'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Synthetic data. Network requests are blocked. Native file selection reads only the file you choose.',
          ),
        ],
        builder: (context) => MaterialApp(
          key: ValueKey((_screen, _revision)),
          debugShowCheckedModeBanner: false,
          theme: Theme.of(context),
          scrollBehavior: ScrollConfiguration.of(context),
          home: _content(),
        ),
      ),
    ),
  );
}
