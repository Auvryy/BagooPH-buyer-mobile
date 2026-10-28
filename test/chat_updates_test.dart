import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

Map<String, dynamic> message(int id, String text, {bool mine = false}) => {
  'id': id,
  'sender_id': mine ? 7 : 3,
  'receiver_id': mine ? 3 : 7,
  'message': text,
  'created_at': '2026-10-28T00:00:00Z',
};

class UpdatingChat extends FakeBuyerRepository {
  int reads = 0;
  final sends = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> rows = [message(1, 'First message')];
  Future<List<Map<String, dynamic>>> Function()? read;
  @override
  Future<List<Map<String, dynamic>>> messages(int receiver) async {
    reads++;
    return read == null ? List.of(rows) : read!();
  }

  @override
  Future<Map<String, dynamic>> sendMessage(
    Map<String, dynamic> values, {
    List<UploadPart>? files,
  }) async {
    sends.add(Map.of(values));
    final sent = message(2, values['message'], mine: true);
    rows.add(sent);
    return sent;
  }
}

Future<void> open(WidgetTester tester, UpdatingChat repo) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: BagooTheme.light,
      home: ChatPage(repository: repo, userId: 7, receiverId: 3),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('connection feedback fits above an enlarged keyboard composer', (
    tester,
  ) async {
    const size = Size(700, 375);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final repo = UpdatingChat();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            viewInsets: EdgeInsets.only(bottom: 150),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: ChatPage(repository: repo, userId: 7, receiverId: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Preserved landscape draft');
    repo.read = () async => throw const BackendException(
      'The connection is temporarily unavailable. Please check your network.',
    );
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Preserved landscape draft',
    );
    expect(find.byTooltip('Send message').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('incoming messages update once without replacing the draft', (
    tester,
  ) async {
    final repo = UpdatingChat();
    addTearDown(repo.session.close);
    await open(tester, repo);
    await tester.enterText(find.byType(TextField), 'My unsent question');
    repo.rows.addAll([message(3, 'New reply'), message(3, 'New reply')]);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('New reply'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'My unsent question',
    );
    expect(repo.sends, isEmpty);
    expect(repo.reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late polling cannot overwrite a confirmed send', (tester) async {
    final repo = UpdatingChat();
    addTearDown(repo.session.close);
    await open(tester, repo);
    final pending = Completer<List<Map<String, dynamic>>>();
    repo.read = () => pending.future;
    await tester.enterText(find.byType(TextField), 'Explicit send');
    await tester.pump(const Duration(seconds: 8));
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(repo.sends, hasLength(1));
    expect(find.text('Explicit send'), findsOneWidget);
    repo.read = null;
    pending.complete([message(1, 'First message')]);
    await tester.pumpAndSettle();
    expect(find.text('Explicit send'), findsOneWidget);
    expect(repo.sends, hasLength(1));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'connection errors retain messages and draft, then recover with backoff',
    (tester) async {
      final repo = UpdatingChat();
      addTearDown(repo.session.close);
      await open(tester, repo);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      repo.read = () async =>
          throw const BackendException('Connection unavailable.');
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(find.text('First message'), findsOneWidget);
      expect(find.textContaining('Retrying automatically'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      expect(repo.reads, 2);
      repo.read = null;
      repo.rows.add(message(3, 'Recovered'));
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(find.text('Recovered'), findsOneWidget);
      expect(find.textContaining('Retrying automatically'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this draft',
      );
      expect(repo.sends, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'denied or changed accounts clear private content and halt refresh',
    (tester) async {
      final repo = UpdatingChat();
      addTearDown(repo.session.close);
      await open(tester, repo);
      await tester.enterText(find.byType(TextField), 'Private draft');
      repo.session.clear();
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(find.text('First message'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final reads = repo.reads;
      await tester.pump(const Duration(minutes: 5));
      expect(repo.reads, reads);
      expect(repo.sends, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
