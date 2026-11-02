import 'dart:async';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bag_fixtures.dart';
import 'support/no_network.dart';

void main() {
  final overrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = overrides);
  late ReviewBagRepository repository;
  late BagController bag;
  setUp(() {
    repository = ReviewBagRepository();
    bag = BagController(repository);
  });
  tearDown(() {
    bag.dispose();
    repository.session.close();
  });
  void privateStateCleared() {
    expect(bag.data, isNull);
    expect(bag.items, isEmpty);
    expect(bag.selected, isEmpty);
    expect(bag.quote, isNull);
    expect(bag.offers, isEmpty);
    expect(bag.ready, isFalse);
    expect(bag.canChange, isFalse);
  }

  for (final status in ['guest', 'active', 'pending_approval']) {
    test('$status can keep using the same session Bag', () async {
      repository.owner = status == 'guest'
          ? null
          : {...repository.owner!, 'status': status};
      await bag.load();
      expect(bag.canChange, isTrue);
      expect(bag.selected, {1});
      expect(await bag.change(1, 2), isTrue);
      expect(bag.items.single['quantity'], 2);
      expect(await bag.change(1, null), isTrue);
      expect(bag.items, isEmpty);
      expect(repository.changes, [(1, 2), (1, null)]);
    });
  }

  for (final status in ['inactive', 'suspended']) {
    test('$status can view but cannot change the Bag', () async {
      repository.owner = {...repository.owner!, 'status': status};
      await bag.load();
      expect(bag.items, isNotEmpty);
      expect(bag.canChange, isFalse);
      expect(await bag.change(1, null), isFalse);
      expect(repository.changes, isEmpty);
    });
  }

  test('an unconfirmed Bag cannot send a guessed item change', () async {
    expect(await bag.change(1, 2), isFalse);
    expect(repository.changes, isEmpty);
  });

  for (final id in [0, -1, 1.5, '1', null]) {
    test(
      'malformed Bag item ID $id cannot become another selected line',
      () async {
        repository.rows = [
          {...repository.rows.single, 'id': id},
        ];
        await bag.load();
        privateStateCleared();
        expect(repository.quotes, isEmpty);
      },
    );
  }

  test(
    'a fractional saved Bag selection is not truncated into a line ID',
    () async {
      repository.read = () async {
        final page = repository.bagDocument();
        page.props['selectedBagItemIds'] = [1.5];
        return page;
      };
      await bag.load();
      expect(bag.selected, isEmpty);
      expect(repository.quotes, isEmpty);
    },
  );

  for (final change in [
    (99, 2),
    (-1, null),
    (1, 0),
    (1, -1),
    (1, 100),
    (1, 4),
  ]) {
    test('invalid item or quantity $change cannot reach a mutation', () async {
      await bag.load();
      expect(await bag.change(change.$1, change.$2), isFalse);
      expect(repository.changes, isEmpty);
      expect(bag.items.single['quantity'], 1);
    });
  }

  test('unavailable items can only be removed', () async {
    repository.rows = [
      {...repository.rows.single, 'available_for_purchase': false},
    ];
    await bag.load();
    expect(await bag.change(1, 2), isFalse);
    expect(repository.changes, isEmpty);
    expect(await bag.change(1, null), isTrue);
    expect(repository.changes, [(1, null)]);
  });

  test('an expired Bag cannot mutate its previous item', () async {
    await bag.load();
    repository.session.clear();
    expect(await bag.change(1, 2), isFalse);
    expect(repository.changes, isEmpty);
    privateStateCleared();
  });

  test('expired selection cannot request another private quote', () async {
    await bag.load();
    final quoteCount = repository.quotes.length;
    repository.session.clear();
    bag.select([1], false);
    await bag.refreshQuote();
    expect(repository.quotes, hasLength(quoteCount));
    privateStateCleared();
  });

  test(
    'expired load does not read a different session into the old Bag',
    () async {
      await bag.load();
      repository.session.clear();
      await bag.load();
      expect(repository.reads, 1);
      privateStateCleared();
    },
  );

  test('a late first Bag cannot repopulate an expired session', () async {
    final pending = Completer<WebPage>();
    repository.read = () => pending.future;
    final loading = bag.load();
    repository.session.clear();
    pending.complete(repository.bagDocument());
    await loading;
    privateStateCleared();
    expect(repository.quotes, isEmpty);
  });

  for (final destination in ['another buyer', 'guest']) {
    test(
      'refresh cannot replace the opening buyer with $destination',
      () async {
        await bag.load();
        repository.owner = destination == 'guest'
            ? null
            : {...repository.owner!, 'id': 8};
        await bag.load();
        privateStateCleared();
      },
    );
  }

  test('a guest Bag cannot silently become a signed-in buyer Bag', () async {
    final buyer = repository.owner;
    repository.owner = null;
    await bag.load();
    repository.owner = buyer;
    await bag.load();
    privateStateCleared();
  });

  for (final fields in [
    {'id': 0},
    {'id': 7.5},
    {'id': '7'},
    {'role': 'seller'},
  ]) {
    test('a malformed opening buyer $fields cannot own Bag rows', () async {
      repository.owner = {...repository.owner!, ...fields};
      await bag.load();
      privateStateCleared();
      expect(repository.quotes, isEmpty);
    });
  }

  for (final action in ['load', 'quote', 'change']) {
    for (final status in [401, 403, 404, 419]) {
      test(
        '$action access denial $status discards private Bag state',
        () async {
          await bag.load();
          final denial = BackendException('Access ended', status: status);
          switch (action) {
            case 'load':
              repository.read = () async => throw denial;
              await bag.load();
            case 'quote':
              repository.selectedQuote = (_) async => throw denial;
              await bag.refreshQuote();
            case 'change':
              repository.change = (_, _) async => throw denial;
              expect(await bag.change(1, 2), isFalse);
          }
          privateStateCleared();
        },
      );
    }
  }

  for (final fails in [false, true]) {
    test(
      'a late ${fails ? 'failed' : 'successful'} quote is private to its session',
      () async {
        await bag.load();
        final confirmed = bag.quote;
        final pending = Completer<Map<String, dynamic>>();
        repository.selectedQuote = (_) => pending.future;
        final quoting = bag.refreshQuote();
        repository.session.clear();
        if (fails) {
          pending.completeError(const BackendException('Private quote failed'));
        } else {
          pending.complete({'quote': confirmed, 'availableVouchers': []});
        }
        await quoting;
        privateStateCleared();
        expect(bag.quoteError, isNull);
      },
    );
  }

  for (final fails in [false, true]) {
    test(
      'a late ${fails ? 'failed' : 'successful'} change cannot restore old rows',
      () async {
        await bag.load();
        final pending = Completer<WebPage>();
        repository.change = (_, _) => pending.future;
        final changing = bag.change(1, 2);
        repository.session.clear();
        if (fails) {
          pending.completeError(const BackendException('Private item failed'));
        } else {
          pending.complete(repository.bagDocument());
        }
        expect(await changing, isFalse);
        privateStateCleared();
        expect(bag.itemErrors, isEmpty);
      },
    );
  }

  test('a mutation reply for a different buyer is not acknowledged', () async {
    await bag.load();
    repository.change = (_, _) async {
      repository.owner = {...repository.owner!, 'id': 8};
      return repository.bagDocument();
    };
    expect(await bag.change(1, 2), isFalse);
    privateStateCleared();
  });

  test(
    'temporary failures keep confirmed rows and allow explicit recovery',
    () async {
      await bag.load();
      repository.read = () async =>
          throw const BackendException('Unavailable', status: 503);
      await bag.load();
      expect(bag.items, hasLength(1));
      expect(bag.error, 'Unavailable');
      expect(bag.ready, isFalse);
      repository.read = null;
      await bag.load();
      expect(bag.ready, isTrue);
    },
  );

  test('repeated changes produce one pending mutation', () async {
    await bag.load();
    final pending = Completer<WebPage>();
    repository.change = (_, _) => pending.future;
    final requests = [for (var n = 0; n < 8; n++) bag.change(1, 2)];
    expect(repository.changes, [(1, 2)]);
    pending.complete(repository.bagDocument());
    await Future.wait(requests);
  });

  for (final expires in [true, false]) {
    test(
      'a changed Bag cannot report success after its follow-up quote loses access: $expires',
      () async {
        await bag.load();
        final confirmed = bag.quote;
        final pending = Completer<Map<String, dynamic>>();
        repository.selectedQuote = (_) => pending.future;
        final changing = bag.change(1, 2);
        await Future<void>.delayed(Duration.zero);
        expect(repository.changes, [(1, 2)]);
        if (expires) {
          repository.session.clear();
          pending.complete({'quote': confirmed, 'availableVouchers': []});
        } else {
          pending.completeError(
            const BackendException('Access ended', status: 403),
          );
        }
        expect(await changing, isFalse);
        privateStateCleared();
      },
    );
  }

  test('the cart owner must agree with its authenticated buyer', () async {
    repository.read = () async => WebPage('Cart/Index', {
      ...repository.bagDocument().props,
      'cart': {'id': 91, 'user_id': 8},
    });
    await bag.load();
    privateStateCleared();
  });

  test('an unexpected page cannot become a Bag', () async {
    repository.read = () async =>
        WebPage('Buyer/Home', repository.bagDocument().props);
    await bag.load();
    privateStateCleared();
  });

  test('a failed update retains rows and needs an explicit retry', () async {
    await bag.load();
    repository.change = (_, _) async =>
        throw const BackendException('Update was not confirmed', status: 503);
    expect(await bag.change(1, 2), isFalse);
    expect(repository.changes, [(1, 2)]);
    expect(bag.items.single['quantity'], 1);
    expect(bag.selected, {1});
    expect(bag.itemErrors[1], 'Update was not confirmed');
    repository.change = null;
    expect(await bag.change(1, 2), isTrue);
    expect(repository.changes, [(1, 2), (1, 2)]);
    expect(bag.items.single['quantity'], 2);
  });

  test('repeated loads share one pending Bag read', () async {
    final pending = Completer<WebPage>();
    repository.read = () => pending.future;
    final requests = [for (var n = 0; n < 8; n++) bag.load()];
    expect(repository.reads, 1);
    pending.complete(repository.bagDocument());
    await Future.wait(requests);
    expect(repository.quotes, hasLength(1));
  });

  test(
    'repeated quote retries coalesce while the same selection is pending',
    () async {
      await bag.load();
      final count = repository.quotes.length;
      final confirmed = bag.quote;
      final pending = Completer<Map<String, dynamic>>();
      repository.selectedQuote = (_) => pending.future;
      final requests = [for (var n = 0; n < 8; n++) bag.refreshQuote()];
      pending.complete({'quote': confirmed, 'availableVouchers': []});
      await Future.wait(requests);
      expect(repository.quotes, hasLength(count + 1));
      expect(bag.ready, isTrue);
    },
  );
}
