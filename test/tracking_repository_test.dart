import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/tracking/tracking_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/tracking_fixtures.dart';

void main() {
  late ControlledWebSession session;
  late TrackingRepository repository;
  setUp(() {
    session = ControlledWebSession();
    repository = TrackingRepository(BuyerRepository(session));
    session.onPage = (_) async => publicTrackingPage();
  });
  tearDown(() => session.close());

  test(
    'normalizes a valid number and rejects invalid numbers before networking',
    () async {
      expect(normalizeTrackingNumber('  bagoo-a_12 \n'), 'BAGOO-A_12');
      expect(normalizeTrackingNumber(List.filled(64, 'a').join()).length, 64);
      for (final value in [
        '',
        ' ',
        '-ABC',
        '_ABC',
        'A/B',
        'A B',
        'A?number=B',
        'A#B',
        'A\nB',
        'ß',
        'é123',
        List.filled(65, 'a').join(),
      ]) {
        await expectLater(
          repository.lookup(value),
          throwsA(isA<BackendException>()),
        );
      }
      expect(session.pageRequests, isEmpty);
    },
  );

  test(
    'accepts only the matching public result and uses supplied labels',
    () async {
      final result = await repository.lookup('  bagoo-1 ');
      expect(session.pageRequests, ['/track?number=BAGOO-1']);
      final parcel = result.parcel!;
      expect(parcel.number, 'BAGOO-1');
      expect(parcel.status, 'delivered');
      expect(parcel.statusLabel, 'Delivered · awaiting buyer confirmation');
      expect(parcel.recipientName, 'B*** T***');
      expect(parcel.milestones.map((entry) => entry.label), [
        'Doorstep handover recorded',
        'Collected from seller',
      ]);
      expect(parcel.milestones.first.location, 'Recipient handoff');
      expect(result.observedAt, DateTime.utc(2026, 10, 27, 8, 30));
      expect(session.posts, isEmpty);
    },
  );

  test(
    'accepts not-found only when the searched number and empty parcel agree',
    () async {
      session.onPage = (_) async => publicTrackingPage(notFound: true);
      final result = await repository.lookup('BAGOO-1');
      expect(result.number, 'BAGOO-1');
      expect(result.parcel, isNull);
      final contradictory = publicTrackingPage();
      contradictory.props['notFound'] = true;
      session.onPage = (_) async => contradictory;
      await expectLater(
        repository.lookup('BAGOO-1'),
        throwsA(isA<BackendException>()),
      );
    },
  );

  test(
    'rejects mismatched numbers, other pages, and incomplete public data',
    () async {
      final cases = [
        WebPage('Buyer/OrderDetail', publicTrackingProps()),
        publicTrackingPage(number: 'OTHER-2'),
        WebPage('Public/Tracking', {...publicTrackingProps(), 'parcel': null}),
        WebPage('Public/Tracking', {
          ...publicTrackingProps(),
          'statusLabels': null,
        }),
        WebPage('Public/Tracking', {
          ...publicTrackingProps(),
          'notFound': null,
        }),
      ];
      final wrongParcel = publicTrackingPage();
      (wrongParcel.props['parcel'] as Map)['tracking_number'] = 'OTHER-2';
      cases.add(wrongParcel);
      final badCheckpoint = publicTrackingPage();
      (badCheckpoint.props['parcel'] as Map)['checkpoints'] = ['invalid'];
      cases.add(badCheckpoint);
      for (final page in cases) {
        session.onPage = (_) async => page;
        await expectLater(
          repository.lookup('BAGOO-1'),
          throwsA(isA<BackendException>()),
        );
      }
    },
  );

  test(
    'preserves server validation feedback and has factual unknown fallbacks',
    () async {
      final rejected = publicTrackingPage();
      rejected.props['validationMessage'] =
          'This tracking number was rejected.';
      session.onPage = (_) async => rejected;
      await expectLater(
        repository.lookup('BAGOO-1'),
        throwsA(
          isA<BackendException>().having(
            (error) => error.fields['number'],
            'number feedback',
            'This tracking number was rejected.',
          ),
        ),
      );
      final unknown = publicTrackingPage(status: 'new_status');
      final data = unknown.props['parcel'] as Map;
      data['estimated_delivery_at'] = null;
      data['delivered_at'] = 'not a date';
      (data['checkpoints'] as List).first['checkpoint_type'] = 'future_event';
      session.onPage = (_) async => unknown;
      final parcel = (await repository.lookup('BAGOO-1')).parcel!;
      expect(parcel.statusLabel, 'Status recorded');
      expect(parcel.milestones.last.label, 'Parcel milestone');
      expect(parcel.estimatedDeliveryAt, isNull);
      expect(parcel.deliveredAt, isNull);
    },
  );

  test('formats Philippine times independently of the device timezone', () {
    expect(
      trackingTime(DateTime.utc(2026, 10, 27, 20, 5)),
      '28 Oct 2026, 4:05 AM',
    );
    expect(
      trackingTime(DateTime.utc(2026, 10, 27, 16)),
      '28 Oct 2026, 12:00 AM',
    );
    expect(
      trackingTime(null, missing: 'Not yet scheduled'),
      'Not yet scheduled',
    );
  });

  for (final inertia in [false, true]) {
    test('uses the existing page transport, inertia=$inertia', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final transport = WebSession(Uri.parse('http://localhost:$port'));
      addTearDown(transport.close);
      addTearDown(() => server.close(force: true));
      final reads = <String>[];
      String markup(Map<String, dynamic> page) {
        final serialized = const HtmlEscape().convert(jsonEncode(page));
        return '<html><div data-page="$serialized"></div></html>';
      }

      server.listen((request) async {
        reads.add(request.uri.path);
        if (request.uri.path == '/bootstrap') {
          request.response.write(
            markup({
              'component': 'Auth/Login',
              'props': <String, dynamic>{},
              'version': 'v1',
            }),
          );
        } else {
          expect(request.method, 'GET');
          expect(request.uri.path, '/track');
          expect(request.uri.queryParameters, {'number': 'BAGOO-1'});
          expect(
            request.headers.value(HttpHeaders.acceptHeader),
            contains('text/html'),
          );
          expect(request.headers.value('X-Inertia'), inertia ? 'true' : isNull);
          final page = {
            'component': 'Public/Tracking',
            'props': publicTrackingProps(),
            'version': 'v1',
          };
          if (inertia) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(page));
          } else {
            request.response.write(markup(page));
          }
        }
        await request.response.close();
      });
      if (inertia) await transport.page('/bootstrap');
      final result = await TrackingRepository(BuyerRepository(transport))
          .lookup('bagoo-1');
      expect(
        result.parcel!.statusLabel,
        'Delivered · awaiting buyer confirmation',
      );
      expect(reads.where((path) => path == '/track'), hasLength(1));
    });
  }
}
