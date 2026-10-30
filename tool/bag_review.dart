import 'dart:io';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../test/support/bag_fixtures.dart';
import '../test/support/no_network.dart';
import 'preview/buyer_device_preview.dart';

void main() {
  if (!kDebugMode || !Platform.isLinux) {
    throw UnsupportedError('The isolated Bag review requires debug Linux.');
  }
  HttpOverrides.global = NoNetworkHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BagReview());
}

class _BagReview extends StatefulWidget {
  const _BagReview();
  @override
  State<_BagReview> createState() => _BagReviewState();
}

class _BagReviewState extends State<_BagReview> {
  static const modes = {
    'ready': 'Successful response',
    'offline': 'Connection failure',
    'denied': 'Access denied',
    'foreign': 'Wrong buyer reply',
  };
  ReviewBagRepository? _repository;
  String _mode = 'ready';
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _repository?.session.close();
    final repository = _repository = ReviewBagRepository();
    _revision++;
    void tick() => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(repository, _repository)) setState(() {});
    });
    Future<void> response(String mode) async {
      tick();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || !identical(repository, _repository)) {
        throw const BackendException(
          'This synthetic Bag was reset.',
          status: 401,
        );
      }
      if (mode == 'offline' || mode == 'denied') {
        throw BackendException(
          mode == 'offline'
              ? 'The synthetic connection is unavailable. Refresh your Bag to review the saved result.'
              : 'Access to this synthetic Bag ended.',
          status: mode == 'offline' ? 503 : 403,
        );
      }
    }

    WebPage page(String mode) {
      final result = repository.bagDocument();
      if (mode != 'foreign') return result;
      return WebPage('Cart/Index', {
        ...result.props,
        'auth': {
          'user': {...repository.owner!, 'id': 99},
        },
        'cart': {'id': 92, 'user_id': 99},
      });
    }

    repository.read = () async {
      final mode = _mode;
      await response(mode);
      return page(mode);
    };
    repository.change = (id, quantity) async {
      final mode = _mode;
      await response(mode);
      repository.rows = [
        for (final row in repository.rows)
          if (row['id'] != id)
            row
          else if (quantity != null)
            {...row, 'quantity': quantity},
      ];
      return page(mode);
    };
    repository.selectedQuote = (ids) async {
      final mode = _mode;
      await response(mode);
      return repository.quoteRows(ids);
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
            'Buyer Bag review',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Next response'),
            items: [
              for (final mode in modes.entries)
                DropdownMenuItem(value: mode.key, child: Text(mode.value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(_reset),
            child: const Text('Reset test Bag'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _repository!.session.clear();
              _repository!.owner = {..._repository!.owner!, 'id': 8};
            }),
            child: const Text('Change test account'),
          ),
          const SizedBox(height: 12),
          Text('Bag reads: ${_repository!.reads}'),
          Text('Quote attempts: ${_repository!.quotes.length}'),
          Text('Mutation attempts: ${_repository!.changes.length}'),
          const SizedBox(height: 12),
          const Text(
            'Synthetic buyer, stock, prices and replies. Outbound requests are blocked. No real Bag or order is changed.',
          ),
        ],
        builder: (context) => MaterialApp(
          key: ValueKey(_revision),
          theme: Theme.of(context),
          debugShowCheckedModeBanner: false,
          scrollBehavior: ScrollConfiguration.of(context),
          home: BagPage(repository: _repository!),
        ),
      ),
    ),
  );
}
