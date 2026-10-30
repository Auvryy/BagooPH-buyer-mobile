import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';

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
