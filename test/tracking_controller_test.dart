import 'dart:async';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/tracking/tracking_controller.dart';
import 'package:bagoo_buyer_mobile/features/tracking/tracking_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/tracking_fixtures.dart';

void main() {
  late ControlledWebSession session;
  late TrackingController controller;
  setUp(() {
    session = ControlledWebSession();
    controller = TrackingController(
      TrackingRepository(BuyerRepository(session)),
    );
  });
  tearDown(() {
    controller.dispose();
    session.close();
  });

  test('a newer search supersedes a slow earlier response', () async {
    final first = Completer<WebPage>();
    session.onPage = (path) => path.contains('FIRST')
        ? first.future
        : Future.value(publicTrackingPage(number: 'SECOND'));
    final pending = controller.lookup('FIRST');
    await controller.lookup('SECOND');
    first.complete(publicTrackingPage(number: 'FIRST'));
    await pending;
    expect(controller.result!.number, 'SECOND');
    expect(controller.loading, isFalse);
  });

  test(
    'editing invalidates an active lookup and removes its previous result',
    () async {
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      final request = controller.lookup('BAGOO-1');
      controller.edited();
      pending.complete(publicTrackingPage());
      await request;
      expect(controller.result, isNull);
      expect(controller.loading, isFalse);
      expect(controller.problem, isNull);
    },
  );

  test('duplicate pending numbers create one lookup and disposal ignores completion', () async {
    final pending = Completer<WebPage>();
    session.onPage = (_) => pending.future;
    final request = controller.lookup('BAGOO-1');
    await controller.lookup(' bagoo-1 ');
    expect(session.pageRequests, hasLength(1));
    controller.dispose();
    pending.complete(publicTrackingPage());
    await request;
    expect(controller.result, isNull);
    // Replace the disposed controller for the shared teardown.
    controller = TrackingController(
      TrackingRepository(BuyerRepository(session)),
    );
  });

  test(
    'refresh failures preserve a dated snapshot until confirmed retry succeeds',
    () async {
      session.onPage = (_) async => publicTrackingPage();
      await controller.lookup('BAGOO-1');
      final confirmed = controller.result;
      session.onPage = (_) async => throw const BackendException('Offline');
      await controller.refresh();
      expect(identical(controller.result, confirmed), isTrue);
      expect(controller.problem, 'Offline');
      session.onPage = (_) async => publicTrackingPage(
        status: 'completed',
        observedAt: '2026-10-27T09:00:00Z',
      );
      await controller.refresh();
      expect(controller.result!.parcel!.status, 'completed');
      expect(controller.result!.observedAt, DateTime.utc(2026, 10, 27, 9));
      expect(controller.problem, isNull);
    },
  );

  test(
    'new searches clear old parcels and local invalid input makes no request',
    () async {
      session.onPage = (_) async => publicTrackingPage();
      await controller.lookup('BAGOO-1');
      final reads = session.pageRequests.length;
      await controller.lookup('invalid/path');
      expect(controller.fieldError, isNotNull);
      expect(controller.result, isNull);
      expect(session.pageRequests.length, reads);
      session.onPage = (_) async => throw const BackendException('Unavailable');
      await controller.lookup('OTHER-2');
      expect(controller.result, isNull);
      expect(controller.problem, 'Unavailable');
    },
  );
}
