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
  'eligible': true,
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

Map<String, dynamic> reviewChoices(int page, {int last = 3}) => {
  'offers': {
    'current_page': page,
    'last_page': last,
    'data': [
      {
        ...reviewOffer(revision: page + 10),
        'name': 'Private voucher choice $page',
        'saving': 10,
      },
    ],
  },
};

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
