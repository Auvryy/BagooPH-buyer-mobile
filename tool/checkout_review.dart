import 'dart:io';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../test/support/checkout_fixtures.dart';
import '../test/support/fake_buyer_repository.dart';
import '../test/support/no_network.dart';
import 'preview/buyer_device_preview.dart';

void main() {
  if (!kDebugMode || !Platform.isLinux) {
    throw UnsupportedError(
      'The isolated checkout review requires debug Linux.',
    );
  }
  HttpOverrides.global = NoNetworkHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _CheckoutReview());
}

class _ReviewRepository extends FakeBuyerRepository {
  late Future<WebPage> Function() reload;
  @override
  Future<WebPage> document(String path) {
    return switch (session.resolve(path).path) {
      '/checkout' => reload(),
      '/buyer/orders' => Future.value(ownedOrderResult()),
      _ => throw const BackendException('This isolated route has no fixture.'),
    };
  }
}

class _CheckoutReview extends StatefulWidget {
  const _CheckoutReview();
  @override
  State<_CheckoutReview> createState() => _CheckoutReviewState();
}

class _CheckoutReviewState extends State<_CheckoutReview> {
  static const modes = {
    'ready': 'Successful response',
    'offline': 'Connection failure',
    'denied': 'Access denied',
    'foreign-result': 'Wrong buyer reply',
    'invalid-location': 'Invalid GPS reading',
  };
  _ReviewRepository? _repository;
  late WebPage _initial;
  String _mode = 'ready';
  int _revision = 0, _quotes = 0;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  Future<void> _response(String mode) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mode == 'offline' || mode == 'denied') {
      throw BackendException(
        mode == 'offline'
            ? 'The synthetic connection is unavailable. Review the saved result before retrying.'
            : 'Access to this synthetic buyer checkout ended.',
        status: mode == 'offline' ? 503 : 403,
      );
    }
  }

  void _reset() {
    _repository?.session.close();
    final repository = _repository = _ReviewRepository()..signedIn = true;
    _initial = ownedCheckout();
    ((_initial.props['addresses'] as List).first as Map<String, dynamic>)
        .addAll({'latitude': '14.0689', 'longitude': '121.3250'});
    _revision++;
    _quotes = 0;
    void checkScene() {
      if (!mounted || !identical(repository, _repository)) {
        throw const BackendException(
          'The isolated checkout was reset.',
          status: 401,
        );
      }
    }

    repository.quoteHandler = (_) async {
      final mode = _mode;
      _quotes++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(repository, _repository)) setState(() {});
      });
      await _response(mode);
      checkScene();
      return confirmedQuote();
    };
    repository.orderHandler = (_) async {
      final mode = _mode;
      if (mounted) setState(() {});
      await _response(mode);
      checkScene();
      return ownedOrderResult(owner: mode == 'foreign-result' ? 8 : 7);
    };
    repository.reload = () async {
      final mode = _mode;
      await _response(mode);
      checkScene();
      return ownedCheckout();
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
          const Text(
            'Buyer checkout review',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
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
            child: const Text('Reset test checkout'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _repository!.session.clear()),
            child: const Text('Change test account'),
          ),
          const SizedBox(height: 12),
          Text('Quote attempts: $_quotes'),
          Text('Synthetic order writes: ${_repository!.orderCalls}'),
          const SizedBox(height: 12),
          const Text(
            'Synthetic buyer, prices and replies. Outbound requests are blocked. No real order, payment or device location is used.',
          ),
        ],
        builder: (context) => MaterialApp(
          key: ValueKey(_revision),
          theme: Theme.of(context),
          debugShowCheckedModeBanner: false,
          scrollBehavior: ScrollConfiguration.of(context),
          home: CheckoutPage(
            repository: _repository!,
            initial: _initial,
            captureLocation: () async {
              final mode = _mode;
              await _response(mode);
              if (mode == 'invalid-location') {
                return (
                  latitude: double.nan,
                  longitude: 121.3250,
                  accuracy: 8.0,
                );
              }
              return (latitude: 14.0689, longitude: 121.3250, accuracy: 8.0);
            },
          ),
        ),
      ),
    ),
  );
}
