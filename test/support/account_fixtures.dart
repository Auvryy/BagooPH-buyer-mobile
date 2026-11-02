import 'dart:convert';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';

import 'fake_buyer_repository.dart' show buyer;
import 'return_fixtures.dart';

typedef AccountMutation = ({
  String path,
  String method,
  Map<String, dynamic> values,
  List<UploadPart> files,
});

class AccountFixtureRepository extends ProfileRepository {
  AccountFixtureRepository() : super(BuyerRepository(ReturnSession()));
  final calls = <AccountMutation>[];
  Future<Map<String, dynamic>> Function(AccountMutation)? onJson;
  Future<WebPage> Function(AccountMutation)? onMutation;

  AccountMutation _record(
    String path,
    Map<String, dynamic> values,
    String method,
    List<UploadPart>? files,
  ) {
    final request = (
      path: path,
      method: method,
      values: Map<String, dynamic>.from(jsonDecode(jsonEncode(values)) as Map),
      files: List<UploadPart>.of(files ?? const []),
    );
    calls.add(request);
    return request;
  }

  @override
  Future<Map<String, dynamic>> json(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    List<UploadPart>? files,
  }) async {
    final request = _record(endpoint, values, method, files);
    if (onJson == null) {
      throw StateError('Unexpected account mutation: $endpoint');
    }
    return onJson!(request);
  }

  @override
  Future<WebPage> mutate(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    String tab = 'account',
    List<UploadPart>? files,
    bool requireMessage = true,
  }) async {
    final request = _record(endpoint, values, method, files);
    if (onMutation == null) {
      throw StateError('Unexpected profile mutation: $endpoint');
    }
    return onMutation!(request);
  }
}

WebPage accountPage({int owner = 7, String token = ''}) =>
    WebPage('Buyer/Profile', {
      'auth': {
        'user': {...buyer, 'id': owner},
      },
      'user': {
        ...buyer,
        'id': owner,
        'email': 'primary@example.test',
        'kyc_status': 'approved',
        'id_document_path': '/buyer/kyc/document',
      },
      'emailSettings': {
        'original': 'primary@example.test',
        'can_manage': true,
        'addresses': [
          {
            'id': 1,
            'email': 'primary@example.test',
            'is_original': true,
            'verified': true,
            'preferred': true,
          },
          {
            'id': 2,
            'email': 'contact@example.test',
            'is_original': false,
            'verified': true,
            'preferred': false,
          },
        ],
      },
      'wallet': {
        'available': true,
        'can_request': true,
        'balance_cents': 12345,
        'credit_requests': [],
      },
      'identityCorrection': {
        'subject': {
          'id': owner,
          'role': 'buyer',
          'name': 'Synthetic Buyer',
          'source_token': token.isEmpty ? 'a' * 64 : token,
          'shop_id': null,
          'values': {
            'birthday': '2000-01-01',
            'first_name': 'Synthetic',
            'sex': 'Male',
          },
          'fields': [
            {'key': 'birthday', 'label': 'Birth date', 'type': 'date'},
            {
              'key': 'first_name',
              'label': 'First name',
              'type': 'text',
              'required': true,
            },
            {
              'key': 'sex',
              'label': 'Sex',
              'type': 'select',
              'options': ['Male', 'Female'],
            },
          ],
          'required_documents': ['id'],
          'requests': [],
        },
      },
    });

Map<String, dynamic> accountSessions({int owner = 7}) {
  const currentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const otherId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  Map<String, dynamic> entry(String id, {bool current = false}) => {
    'id': id,
    'device': current ? 'Current QA session' : 'Private other device',
    'device_type': 'phone',
    'channel': 'mobile',
    'method': 'password',
    'network': null,
    'current': current,
    'active': true,
    'status': 'active',
    'signed_in_at': '2026-10-01T00:00:00Z',
    'last_seen_at': '2026-10-28T00:00:00Z',
    'ended_at': null,
  };
  final entries = [entry(currentId, current: true), entry(otherId)];
  Map<String, dynamic> page() {
    final rows = entries
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    return {
      'data': rows,
      'current_page': 1,
      'last_page': 1,
      'total': rows.length,
      'per_page': 12,
      'from': rows.isEmpty ? null : 1,
      'to': rows.length,
    };
  }

  return {
    'sessionOwnerId': owner,
    'currentSessionId': currentId,
    'canConfirmByEmail': true,
    'historyDays': 30,
    'lastSignIn': entry(currentId, current: true),
    'sessions': page(),
    'signIns': page(),
  };
}

WebPage applicationPage() {
  final page = accountPage();
  final user = {
    ...mapOf(page.props['user']),
    'kyc_status': 'rejected',
    'status': 'pending_approval',
  };
  page.props['user'] = user;
  page.props['auth'] = {'user': user};
  page.props['identityCorrection'] = {'subject': null};
  page.props['buyerApplication'] = {
    'user': user,
    'can_use_portal': false,
    'application': {
      'can_correct': true,
      'values': {'first_name': 'Synthetic', 'birthday': '2000-01-01'},
      'fields': [
        {
          'key': 'first_name',
          'label': 'First name',
          'type': 'text',
          'required': true,
          'min_length': 2,
          'max_length': 100,
          'options': [],
        },
        {
          'key': 'middle_name',
          'label': 'Middle name / initial',
          'type': 'text',
          'required': false,
          'min_length': 1,
          'max_length': 50,
          'options': [],
        },
        {
          'key': 'last_name',
          'label': 'Last name',
          'type': 'text',
          'required': false,
          'min_length': 2,
          'max_length': 50,
          'options': [],
        },
        {
          'key': 'sex',
          'label': 'Sex',
          'type': 'select',
          'required': true,
          'min_length': 2,
          'max_length': 255,
          'options': ['Female', 'Male', 'Other'],
        },
        {
          'key': 'email',
          'label': 'Account email',
          'type': 'email',
          'required': true,
          'min_length': null,
          'max_length': 255,
          'options': [],
        },
        {
          'key': 'phone',
          'label': 'Account mobile number',
          'type': 'tel',
          'required': false,
          'min_length': null,
          'max_length': 24,
          'options': [],
        },
        {
          'key': 'address',
          'label': 'Street address',
          'type': 'text',
          'required': false,
          'min_length': 5,
          'max_length': 500,
          'options': [],
        },
        {
          'key': 'city',
          'label': 'City',
          'type': 'text',
          'required': false,
          'min_length': 2,
          'max_length': 255,
          'options': [],
        },
        {
          'key': 'province',
          'label': 'Province',
          'type': 'text',
          'required': false,
          'min_length': 2,
          'max_length': 255,
          'options': [],
        },
        {
          'key': 'municipality',
          'label': 'Municipality',
          'type': 'text',
          'required': false,
          'min_length': 2,
          'max_length': 255,
          'options': [],
        },
        {
          'key': 'barangay',
          'label': 'Barangay',
          'type': 'text',
          'required': false,
          'min_length': 2,
          'max_length': 255,
          'options': [],
        },
        {
          'key': 'postal_code',
          'label': 'Postal code',
          'type': 'text',
          'required': false,
          'min_length': 4,
          'max_length': 4,
          'input_mode': 'numeric',
          'options': [],
        },
      ],
    },
    'birth_date_limits': {'adult_maximum': '2008-01-01'},
    'identity_document_url': '/buyer/kyc/document',
  };
  return page;
}
