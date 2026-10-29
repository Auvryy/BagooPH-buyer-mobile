import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/return_fixtures.dart';

void main() {
  late ReturnSession session;
  late ProfileRepository repository;
  setUp(() {
    session = ReturnSession();
    repository = ProfileRepository(BuyerRepository(session));
  });
  tearDown(() => session.close());

  Widget app({String path = '/buyer-returns/4/evidence/1', double scale = 1}) =>
      MaterialApp(
        theme: BagooTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: PrivateDocumentPage(
          key: const ValueKey('document'),
          repository: repository,
          path: path,
          title: 'Private evidence',
        ),
      );

  testWidgets(
    'long document failure remains readable in a short large-text window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 280);
      addTearDown(tester.view.reset);
      session.onDocument = (_) async => throw BackendException(
        'Document access failed. ${'Review your access and try again. ' * 16}',
      );
      await tester.pumpWidget(app(scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final retry = find.text('Try again');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      expect(retry.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('a document finishing after an account change is not displayed', (
    tester,
  ) async {
    final pending = Completer<RemoteDocument>();
    session.onDocument = (_) => pending.future;
    await tester.pumpWidget(app());
    await tester.pump();
    session.clear();
    pending.complete(RemoteDocument(returnPhotoBytes(), 'image/png'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'changing the evidence path starts a new read with no old image',
    (tester) async {
      session.onDocument = (_) async =>
          RemoteDocument(returnPhotoBytes(), 'image/png');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final second = Completer<RemoteDocument>();
      session.onDocument = (_) => second.future;
      await tester.pumpWidget(app(path: '/buyer-returns/4/evidence/2'));
      await tester.pump();
      expect(session.documentRequests, hasLength(2));
      expect(find.byType(Image), findsNothing);
      second.complete(RemoteDocument(returnPhotoBytes(), 'image/png'));
      await tester.pumpAndSettle();
    },
  );
}
