import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';

import 'dart:convert';

import 'checkout_fixtures.dart';

import 'fake_buyer_repository.dart';

Map<String, dynamic> reviewOffer({Object? revision = 12, Object? saved}) => {
  'revision_id': revision,
  'saved_id': saved,
  'name': 'Test voucher',
  'code': 'TEST-OFFER',
  'issuer': 'platform',
  'discount_type': 'fixed',
  'discount_value': 10,
  'min_spend': 0,
  'product_scope': 'all',
  'eligible_products': <Map<String, dynamic>>[],
  'eligible': true,
  'uses': <Map<String, dynamic>>[],
};

class VoucherReviewSession extends FakeSession {
  late final repository = BuyerRepository(this);
  final writes = <(String, String)>[];
  Future<Map<String, dynamic>> Function(String, String)? reply;

  @override
  Future<Map<String, dynamic>> jsonPost(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
  }) async {
    writes.add((path, method));
    return reply == null
        ? {'saved_id': method == 'DELETE' ? null : 21}
        : reply!(path, method);
  }
}

BuyerRepository voucherRepository(VoucherReviewSession session) =>
    session.repository;

Map<String, dynamic> reviewChoices(int page, {int last = 3}) {
  final total = last == 1 ? 1 : (last - 1) * 12 + 1;
  final inRange = page <= last && total > 0;
  final from = inRange ? (page - 1) * 12 + 1 : null;
  final rowCount = !inRange
      ? 0
      : page < last
      ? 12
      : total - (last - 1) * 12;
  return {
    'offers': {
      'current_page': page,
      'last_page': last,
      'per_page': 12,
      'total': total,
      'from': from,
      'to': rowCount == 0 ? null : from! + rowCount - 1,
      'data': [
        for (var index = 0; index < rowCount; index++)
          if (index == 0)
            {
              ...reviewOffer(revision: page + 10),
              'name': 'Private voucher choice $page',
              'saving': 10,
            }
          else
            {
              ...reviewOffer(
                revision: 10000 + page * 12 + index,
                saved: 20000 + page * 12 + index,
              ),
              'name': 'Saved fixture offer $page-$index',
              'eligible': false,
              'saving': 0,
            },
      ],
    },
  };
}

class VoucherPickerReviewRepository extends BuyerRepository {
  VoucherPickerReviewRepository(super.session);
  final choiceRequests = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? choices;
  @override
  Future<Map<String, dynamic>> voucherChoices(
    Map<String, dynamic> values,
  ) async {
    final snapshot = jsonDecode(jsonEncode(values)) as Map<String, dynamic>;
    choiceRequests.add(snapshot);
    return choices == null
        ? reviewChoices(values['voucher_page'] as int)
        : choices!(snapshot);
  }

  @override
  Future<Map<String, dynamic>> quote(Map<String, dynamic> values) async =>
      confirmedQuote();
}
