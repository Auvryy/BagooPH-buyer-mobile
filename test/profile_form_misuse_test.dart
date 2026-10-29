import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/personal_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/wallet_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class ProfileMisuseRepository extends ProfileRepository {
  ProfileMisuseRepository() : super(FakeBuyerRepository());
  final mutations = <Map<String, dynamic>>[];
  final credits = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pendingCredit;
  final page = WebPage('Buyer/Profile', {
    'auth': {'user': buyer},
    'user': {...buyer, 'email_verified_at': '2026-01-01'},
    'wallet': {
      'available': true,
      'can_request': true,
      'balance_cents': 0,
      'credit_requests': [],
    },
  });

  @override
  Future<WebPage> mutate(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    String tab = 'account',
    List<UploadPart>? files,
    bool requireMessage = true,
  }) async {
    mutations.add(Map.of(values));
    return page;
  }

  @override
  Future<Map<String, dynamic>> json(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    List<UploadPart>? files,
  }) {
    credits.add(Map.of(values));
    return pendingCredit?.future ??
        Future.value({'reference': 'QA-CREDIT', 'status': 'pending'});
  }
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  late ProfileMisuseRepository repository;
  setUp(() => repository = ProfileMisuseRepository());
  tearDown(() => repository.session.close());

  Future<void> open(WidgetTester tester, {bool wallet = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: wallet
              ? WalletSection(
                  repository: repository,
                  page: repository.page,
                  reload: () async {},
                  onPage: (_) {},
                  onOrder: (_) {},
                )
              : PasswordSection(
                  repository: repository,
                  page: repository.page,
                  onChanged: (_) {},
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final password in ['abcdefgh', '12345678', 'AAAAAAAA', 'Valid1234']) {
    testWidgets('password update rejects a weak password: $password', (
      tester,
    ) async {
      await open(tester);
      for (final entry in {
        'Current password': 'Original!123',
        'New password': password,
        'Confirm new password': password,
      }.entries) {
        final field = find.widgetWithText(TextFormField, entry.key);
        tester.widget<TextFormField>(field).controller!.text = entry.value;
      }
      final submit = find.widgetWithText(FilledButton, 'Update password');
      await reveal(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.mutations, isEmpty);
    });
  }

  testWidgets('invalid wallet amounts never create a credit request', (
    tester,
  ) async {
    await open(tester, wallet: true);
    final amount = find.widgetWithText(TextFormField, 'Amount (PHP)');
    final reason = find.widgetWithText(TextFormField, 'Reason');
    tester.widget<TextFormField>(reason).controller!.text =
        'Synthetic QA credit';
    for (final value in [
      '',
      ' ',
      'NaN',
      'Infinity',
      '1e2',
      '-1',
      '0',
      '0.99',
      '100000.01',
      '1.001',
      '1,000',
      '１２',
    ]) {
      tester.widget<TextFormField>(amount).controller!.text = value;
      final submit = find.widgetWithText(FilledButton, 'Request credits');
      await reveal(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.credits, isEmpty, reason: value);
    }
  });

  testWidgets(
    'repeated credit taps send once and uncertain retry reuses intent',
    (tester) async {
      await open(tester, wallet: true);
      tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Amount (PHP)'),
              )
              .controller!
              .text =
          '25.50';
      tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Reason'),
              )
              .controller!
              .text =
          'Synthetic QA credit';
      final pending = repository.pendingCredit =
          Completer<Map<String, dynamic>>();
      final submit = find.widgetWithText(FilledButton, 'Request credits');
      await reveal(tester, submit);
      for (var i = 0; i < 8; i++) {
        await tester.tap(submit);
      }
      expect(repository.credits, hasLength(1));
      final original = Map.of(repository.credits.single);
      pending.completeError(const BackendException('Result uncertain.'));
      await tester.pumpAndSettle();
      repository.pendingCredit = null;
      final retry = find.widgetWithText(
        FilledButton,
        'Retry same credit request',
      );
      await reveal(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repository.credits, [original, original]);
      expect(find.textContaining('recorded: pending'), findsOneWidget);
    },
  );
}
