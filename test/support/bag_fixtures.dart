import 'package:bagoo_buyer_mobile/core/web_session.dart';

import 'fake_buyer_repository.dart';

Map<String, dynamic> line(int id, {String color = 'Red', int quantity = 1}) => {
  'id': id,
  'product_id': 10,
  'color': color,
  'size': 'M',
  'quantity': quantity,
  'unit_price': 100,
  'available_for_purchase': true,
  'product': {
    'id': 10,
    'name': 'Test product',
    'slug': 'test-product',
    'price': 100,
    'stock': 20,
    'shop_id': 1,
    'shop': {'id': 1, 'name': 'Test shop'},
    'variants': {
      'colors': [
        {'name': 'Red'},
        {'name': 'Blue'},
      ],
      'sizes': [
        {'name': 'M', 'stock': 4},
      ],
      'combinations': [
        {'color': 'Red', 'size': 'M', 'stock': 3},
        {'color': 'Blue', 'size': 'M', 'stock': 8},
      ],
    },
  },
};
Map<String, dynamic> priced(List<int> ids) => {
  'quote': {
    'subtotal': ids.length * 100,
    'shipping_fee': 50,
    'discount': 0,
    'shipping_discount': 0,
    'voucher': null,
    'vouchers': <Map<String, dynamic>>[],
    'voucher_error': null,
    'redemptions': <Map<String, dynamic>>[],
    'total': ids.length * 100 + 50,
    'items': [
      for (final id in ids)
        {'id': id, 'quantity': 1, 'unit_price': 100, 'subtotal': 100},
    ],
    'shops': [
      {
        'shop_id': 1,
        'shop_name': 'Test shop',
        'subtotal': ids.length * 100,
        'shipping': 50,
        'discount': 0,
        'product_discount': 0,
        'shipping_discount': 0,
        'total': ids.length * 100 + 50,
      },
    ],
  },
  'availableVouchers': [],
};

class ReviewBagRepository extends FakeBuyerRepository {
  Map<String, dynamic>? owner = Map.of(buyer);
  List<Map<String, dynamic>> rows = [
    {
      ...line(1),
      'product': {...mapOf(line(1)['product']), 'name': 'Private Bag product'},
    },
  ];
  Future<WebPage> Function()? read;
  Future<WebPage> Function(int, int?)? change;
  Future<Map<String, dynamic>> Function(List<int>)? selectedQuote;
  int reads = 0;
  final changes = <(int, int?)>[];
  final quotes = <List<int>>[];

  WebPage bagDocument() => WebPage('Cart/Index', {
    'auth': {'user': owner},
    'cart': {'id': 91, 'user_id': owner?['id']},
    'items': rows,
  });

  @override
  Future<WebPage> bag() async {
    reads++;
    return read == null ? bagDocument() : read!();
  }

  @override
  Future<Map<String, dynamic>> bagQuote(List<int> ids) async {
    quotes.add([...ids]);
    if (selectedQuote != null) return selectedQuote!(ids);
    return quoteRows(ids);
  }

  Map<String, dynamic> quoteRows(List<int> ids) {
    final selected = rows.where((row) => ids.contains(row['id'])).toList();
    final subtotal = selected.fold<int>(
      0,
      (sum, row) => sum + (row['quantity'] as int) * 100,
    );
    return {
      'quote': {
        ...mapOf(priced(ids)['quote']),
        'subtotal': subtotal,
        'total': subtotal + 50,
        'items': [
          for (final row in selected)
            {
              'id': row['id'],
              'quantity': row['quantity'],
              'unit_price': 100,
              'subtotal': (row['quantity'] as int) * 100,
            },
        ],
        'shops': [
          {
            'shop_id': 1,
            'shop_name': 'Test shop',
            'subtotal': subtotal,
            'shipping': 50,
            'discount': 0,
            'product_discount': 0,
            'shipping_discount': 0,
            'total': subtotal + 50,
          },
        ],
      },
      'availableVouchers': [],
    };
  }

  @override
  Future<WebPage> changeBagItem(int id, int? quantity) async {
    changes.add((id, quantity));
    if (change != null) return change!(id, quantity);
    rows = [
      for (final row in rows)
        if (row['id'] != id)
          row
        else if (quantity != null)
          {...row, 'quantity': quantity},
    ];
    return bagDocument();
  }
}
