import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test/support/no_network.dart';
import '../test/support/pdf_fixture.dart';
import '../test/support/return_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  late ReturnSession session;
  late ProfileRepository repository;
  setUp(() {
    session = ReturnSession();
    repository = ProfileRepository(BuyerRepository(session));
    session.onDocument = (path) async => RemoteDocument(
      evidencePdf(
        path.endsWith('/2') ? 'Second buyer evidence' : 'Buyer QA evidence',
      ),
      'application/pdf',
    );
  });
  tearDown(() => session.close());

  Widget document(String path) => PrivateDocumentPage(
    repository: repository,
    path: path,
    title: 'Private evidence',
  );
  Future<void> open(WidgetTester tester, {bool largeText = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
          child: child!,
        ),
        home: document('/buyer-returns/4/evidence/1'),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<PdfDocumentListenable> loaded(WidgetTester tester) async {
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final result = viewer.documentRef.resolveListenable();
    await tester.runAsync(() => result.load());
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('authenticated PDF bytes render with the native engine', (
    tester,
  ) async {
    await open(tester);
    final result = await loaded(tester);
    expect(result.error, isNull);
    expect(result.document?.pages, hasLength(1));
    await tester.runAsync(() async {
      final page = result.document!.pages.single;
      expect((await page.loadText())?.fullText, contains('Buyer QA evidence'));
      final image = await page.render(
        width: 300,
        height: 180,
        fullWidth: 300,
        fullHeight: 180,
        backgroundColor: 0xffffffff,
      );
      expect(image, isNotNull);
      try {
        var ink = 0;
        for (var index = 0; index < image!.pixels.length; index += 4) {
          if (image.pixels[index] < 240) ink++;
        }
        expect(ink, greaterThan(100));
      } finally {
        image?.dispose();
      }
      expect(
        await page.loadLinks(enableAutoLinkDetection: false),
        hasLength(1),
      );
    });
    expect(session.documentRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-titled evidence routes render their own PDF bytes', (
    tester,
  ) async {
    await open(tester);
    await loaded(tester);
    Navigator.of(tester.element(find.byType(PrivateDocumentPage))).push(
      MaterialPageRoute<void>(
        builder: (_) => document('/buyer-returns/4/evidence/2'),
      ),
    );
    await tester.pumpAndSettle();
    final result = await loaded(tester);
    final text = await tester.runAsync(
      () => result.document!.pages.single.loadText(),
    );
    expect(text?.fullText, contains('Second buyer evidence'));
    expect(text?.fullText, isNot(contains('Buyer QA evidence')));
    expect(session.documentRequests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'corrupt PDF gives readable feedback and a fresh authenticated retry',
    (tester) async {
      session.onDocument = (_) async => RemoteDocument(
        Uint8List.fromList(utf8.encode('This is not a PDF document.')),
        'application/pdf',
      );
      await open(tester, largeText: true);
      await loaded(tester);
      expect(
        find.text(
          'This PDF cannot be displayed. Try again or reopen it from your account.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('errorBannerBuilder'), findsNothing);
      final retry = find.text('Try again');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      expect(retry.hitTestable(), findsOneWidget);
      session.onDocument = (_) async =>
          RemoteDocument(evidencePdf('Recovered evidence'), 'application/pdf');
      await tester.tap(retry);
      await tester.pump();
      await tester.pump();
      final result = await loaded(tester);
      expect(result.error, isNull);
      final text = await tester.runAsync(
        () => result.document!.pages.single.loadText(),
      );
      expect(text?.fullText, contains('Recovered evidence'));
      expect(session.documentRequests, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account expiry removes an already loaded native PDF', (
    tester,
  ) async {
    await open(tester);
    await loaded(tester);
    session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(PdfViewer), findsNothing);
    expect(find.text('Close document'), findsOneWidget);
    expect(session.documentRequests, hasLength(1));
  });
}
