import 'dart:convert';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/core/application_text_validation.dart';
import 'package:bagoo_buyer_mobile/core/form_metadata.dart';
import 'package:bagoo_buyer_mobile/core/pagination_metadata.dart';
import 'package:bagoo_buyer_mobile/core/request_id.dart';
import 'package:bagoo_buyer_mobile/core/resource_ids.dart';
import 'package:bagoo_buyer_mobile/core/strict_datetime.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _page({
  int rows = 2,
  int current = 1,
  int last = 2,
  int total = 3,
  int pageSize = 2,
  int? from = 1,
  int? to = 2,
}) => {
  'data': List.generate(rows, (index) => {'id': index + 1}),
  'current_page': current,
  'last_page': last,
  'total': total,
  'per_page': pageSize,
  'from': from,
  'to': to,
};

void main() {
  group('form metadata rejects unusable server choices', () {
    test('options preserve server values and first occurrence order', () {
      expect(
        uniqueStringOptions(['Passport', 'National ID', 'Passport', ' ID ']),
        ['Passport', 'National ID', ' ID '],
      );
      expect(uniqueStringOptions([]), isEmpty);
    });

    test('a malformed choice invalidates the complete choice list', () {
      for (final value in [null, 'Passport', 1, <String, Object?>{}]) {
        expect(uniqueStringOptions(value), isNull, reason: '$value');
      }
      for (final value in [null, 1, false, '', ' \t\n']) {
        expect(uniqueStringOptions(['Passport', value]), isNull);
      }
    });

    test('negative or reversed default bounds cannot enable a field', () {
      expect(
        parseTextLengthBounds({}, defaultMinimum: -1, defaultMaximum: 20),
        isNull,
      );
      expect(
        parseTextLengthBounds({}, defaultMinimum: 21, defaultMaximum: 20),
        isNull,
      );
    });

    test('null bounds use defaults and explicit zero bounds remain valid', () {
      final defaults = parseTextLengthBounds(
        {'min_length': null, 'max_length': null},
        defaultMinimum: 1,
        defaultMaximum: 20,
      );
      expect(defaults?.minimum, 1);
      expect(defaults?.maximum, 20);

      final zero = parseTextLengthBounds(
        {'min_length': 0, 'max_length': 0},
        defaultMinimum: 1,
        defaultMaximum: 20,
      );
      expect(zero?.minimum, 0);
      expect(zero?.maximum, 0);
    });

    test(
      'explicit malformed bounds never fall back to permissive defaults',
      () {
        for (final key in ['min_length', 'max_length']) {
          for (final value in [-1, 1.0, '1', true, [], double.nan]) {
            expect(
              parseTextLengthBounds(
                {key: value},
                defaultMinimum: 1,
                defaultMaximum: 20,
              ),
              isNull,
              reason: '$key=$value',
            );
          }
        }
        expect(
          parseTextLengthBounds(
            {'min_length': 4, 'max_length': 3},
            defaultMinimum: 1,
            defaultMaximum: 20,
          ),
          isNull,
        );
      },
    );
  });

  group('resource rows fail as one unit', () {
    test('valid rows preserve their custom identifier key and data', () {
      final rows = [
        {'case_id': 1, 'label': 'First'},
        {'case_id': 2147483648, 'label': 'Second'},
      ];
      expect(
        requireRowsWithIds(rows, idKey: 'case_id', error: 'Invalid cases.'),
        rows,
      );
      expect(
        requireRowsWithIds([], idKey: 'case_id', error: 'Invalid cases.'),
        isEmpty,
      );
      expect(positiveResourceIds([2, 2, 1, 1]), {1, 2});
    });

    test(
      'non-lists, malformed rows, invalid and duplicate IDs are rejected',
      () {
        for (final value in [
          null,
          {'case_id': 1},
          [null],
          [1],
          [<String, dynamic>{}],
          [
            {'case_id': 0},
          ],
          [
            {'case_id': -1},
          ],
          [
            {'case_id': 1.0},
          ],
          [
            {'case_id': '1'},
          ],
          [
            {'case_id': 1},
            {'case_id': 1},
          ],
        ]) {
          expect(
            () => requireRowsWithIds(
              value,
              idKey: 'case_id',
              error: 'Invalid cases.',
            ),
            throwsA(
              isA<BackendException>().having(
                (error) => error.message,
                'message',
                'Invalid cases.',
              ),
            ),
            reason: '$value',
          );
        }
      },
    );
  });

  group('pagination metadata boundaries', () {
    test('legacy rows use one page and the actual row count by default', () {
      final result = parsePaginationMetadata({
        'data': [1, 2],
      }, rowCount: 2);
      expect(result?.currentPage, 1);
      expect(result?.lastPage, 1);
      expect(result?.total, 2);
      expect(result?.from, isNull);
      expect(result?.to, isNull);
    });

    test('missing required page numbers and impossible row counts fail', () {
      expect(parsePaginationMetadata({'data': []}, rowCount: -1), isNull);
      for (final value in [
        null,
        [],
        {'data': null},
        {'data': 'rows'},
      ]) {
        expect(parsePaginationMetadata(value, rowCount: 0), isNull);
      }
      expect(
        parsePaginationMetadata({
          'data': [1],
        }, rowCount: 0),
        isNull,
      );
      for (final absentKey in ['current_page', 'last_page']) {
        final value = _page()..remove(absentKey);
        expect(
          parsePaginationMetadata(value, rowCount: 2, requirePageNumbers: true),
          isNull,
        );
      }
    });

    test('page numbers, totals and ranges require exact bounded integers', () {
      for (final key in ['current_page', 'last_page', 'total', 'from', 'to']) {
        for (final value in [-1, '1', 1.0, true, double.infinity]) {
          expect(
            parsePaginationMetadata({..._page(), key: value}, rowCount: 2),
            isNull,
            reason: '$key=$value',
          );
        }
      }
      for (final key in ['current_page', 'last_page', 'from', 'to']) {
        expect(
          parsePaginationMetadata({..._page(), key: 0}, rowCount: 2),
          isNull,
        );
      }
      for (final range in [
        {'from': 2, 'to': 1},
        {'from': 4, 'to': null},
        {'from': null, 'to': 4},
      ]) {
        expect(
          parsePaginationMetadata({..._page(), ...range}, rowCount: 2),
          isNull,
        );
      }
    });

    test('request bounds reject zero, excess and negative counts', () {
      for (final request in [
        (page: 0, size: 2, rows: 2),
        (page: maxBuyerPaginationPage + 1, size: 2, rows: 2),
        (page: 1, size: 0, rows: 0),
        (page: 1, size: 101, rows: 2),
        (page: 1, size: 2, rows: -1),
        (page: 1, size: 2, rows: 3),
      ]) {
        expect(
          parseContractPaginationMetadata(
            _page(),
            rowCount: request.rows,
            requestedPage: request.page,
            pageSize: request.size,
          ),
          isNull,
          reason: '$request',
        );
      }
      expect(isValidBuyerPageRequest(0), isFalse);
      expect(isValidBuyerPageRequest(1), isTrue);
      expect(isValidBuyerPageRequest(maxBuyerPaginationPage), isTrue);
      expect(isValidBuyerPageRequest(maxBuyerPaginationPage + 1), isFalse);
    });

    test(
      'empty results and clamped final pages preserve their exact ranges',
      () {
        final empty = parseContractPaginationMetadata(
          _page(rows: 0, last: 1, total: 0, from: null, to: null),
          rowCount: 0,
          requestedPage: 100,
          pageSize: 2,
        );
        expect(empty?.total, 0);
        expect(empty?.currentPage, 1);
        expect(empty?.lastPage, 1);
        expect(empty?.from, isNull);
        expect(empty?.to, isNull);

        final finalPage = parseContractPaginationMetadata(
          _page(rows: 1, current: 2, from: 3, to: 3),
          rowCount: 1,
          requestedPage: 100,
          pageSize: 2,
        );
        expect(finalPage?.currentPage, 2);
        expect(finalPage?.lastPage, 2);
        expect(finalPage?.total, 3);
        expect(finalPage?.from, 3);
        expect(finalPage?.to, 3);
      },
    );

    test('largest supported page is accepted without offset overflow', () {
      final result = parseContractPaginationMetadata(
        _page(
          rows: 1,
          current: maxBuyerPaginationPage,
          last: maxBuyerPaginationPage,
          total: maxBuyerPaginationPage,
          pageSize: 1,
          from: maxBuyerPaginationPage,
          to: maxBuyerPaginationPage,
        ),
        rowCount: 1,
        requestedPage: maxBuyerPaginationPage,
        pageSize: 1,
      );
      expect(result?.currentPage, maxBuyerPaginationPage);
      expect(result?.from, maxBuyerPaginationPage);
    });

    test(
      'inconsistent authoritative pagination is never silently repaired',
      () {
        for (final change in [
          {'last_page': 3},
          {'current_page': 2},
          {'from': 2},
          {'to': 1},
          {'from': null},
          {'to': null},
          {'total': null},
          {'total': 2 * maxBuyerPaginationPage + 1},
          {'per_page': null},
          {'per_page': '2'},
          {'per_page': 1},
        ]) {
          expect(
            parseContractPaginationMetadata(
              {..._page(), ...change},
              rowCount: 2,
              requestedPage: 1,
              pageSize: 2,
            ),
            isNull,
            reason: '$change',
          );
        }
        expect(
          parseContractPaginationMetadata(
            _page(rows: 1, to: 1),
            rowCount: 1,
            requestedPage: 1,
            pageSize: 2,
          ),
          isNull,
        );
      },
    );
  });

  group('strict server timestamps', () {
    test('non-text inputs and calendar boundaries cannot normalize a date', () {
      for (final value in [null, 20261103, true, <Object?>[]]) {
        expect(strictDateOnly(value), isNull);
        expect(strictDateTime(value), isNull);
      }
      for (final value in [
        '1900-02-29',
        '2026-00-01',
        '2026-13-01',
        '2026-04-31',
        '2026-01-00',
        '2026-11-03\n',
        ' 2026-11-03',
      ]) {
        expect(strictDateOnly(value), isNull, reason: value);
      }
      expect(strictDateOnly('2000-02-29'), DateTime(2000, 2, 29));
    });

    test('fractional seconds and extreme legal offsets retain the instant', () {
      expect(
        strictDateTime('2026-11-03T00:00:00.123456z', requireTimezone: true),
        DateTime.utc(2026, 11, 3, 0, 0, 0, 123, 456),
      );
      expect(
        strictDateTime('2026-11-03T00:00:00+14:00', requireTimezone: true),
        DateTime.utc(2026, 11, 2, 10),
      );
      expect(
        strictDateTime('2026-11-03T00:00:00-14:00', requireTimezone: true),
        DateTime.utc(2026, 11, 3, 14),
      );
      for (final value in [
        '2026-11-03T00:00:00+00:60',
        '2026-11-03T00:00:00-13:60',
        '2026-11-03T00:00:00-14:01',
        '2026-11-03T00:00:00+1400',
      ]) {
        expect(strictDateTime(value, requireTimezone: true), isNull);
      }
    });
  });

  test(
    'multipart nested values retain indices, booleans and empty scalars',
    () {
      final payload = MultipartPayload(
        {
          'items': [
            {'id': 3, 'selected': true},
            {'id': 7, 'selected': false},
          ],
          'optional': null,
          'notes': 'Caf\u00e9\r\nCall on arrival',
          'empty_map': <String, Object?>{},
          'empty_list': <Object?>[],
        },
        [
          UploadPart(
            'proof',
            'proof.bin',
            Uint8List.fromList([0, 255]),
            'x/test',
          ),
        ],
      );
      final body = latin1.decode(payload.bytes);
      for (final entry in {
        'items[0][id]': '3',
        'items[0][selected]': '1',
        'items[1][id]': '7',
        'items[1][selected]': '0',
        'optional': '',
      }.entries) {
        expect(body, contains('name="${entry.key}"\r\n\r\n${entry.value}\r\n'));
      }
      expect(body, isNot(contains('name="empty_map"')));
      expect(body, isNot(contains('name="empty_list"')));
      expect(
        body,
        contains(latin1.decode(utf8.encode('Caf\u00e9\r\nCall on arrival'))),
      );
      expect(body, contains('Content-Type: x/test\r\n\r\n\x00\xff\r\n'));
      expect(body, endsWith('--${payload.boundary}--\r\n'));
    },
  );

  test('empty multipart bodies contain only their terminating boundary', () {
    final payload = MultipartPayload({}, []);
    expect(utf8.decode(payload.bytes), '--${payload.boundary}--\r\n');
  });

  test(
    'request IDs have the UUID version and variant required for retries',
    () {
      expect(
        requestId(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );

  test('optional application values and unhandled fields stay optional', () {
    for (final validator in [
      buyerNameTextError,
      buyerAddressTextError,
      buyerNotesTextError,
    ]) {
      expect(validator(null), isNull);
      expect(validator(''), isNull);
    }
    expect(buyerNameTextError('Ana\u3000Maria'), isNull);
    expect(
      buyerApplicationFieldError('unhandled_field', '<server-owned>'),
      isNull,
    );
    expect(buyerApplicationFieldError('postal_code', null), isNull);
    expect(buyerApplicationFieldError('postal_code', ''), isNull);
  });
}
