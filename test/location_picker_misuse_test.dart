import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class _LocationResponseSession extends FakeSession {
  _LocationResponseSession(this.response);

  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> jsonGet(String path) async {
    if (path.startsWith('/address-locations')) return response;
    return super.jsonGet(path);
  }
}

class _RateLimitedLocationSession extends FakeSession {
  final requests = <String>[];

  @override
  Future<Map<String, dynamic>> jsonGet(String path) async {
    requests.add(path);
    throw BackendException(
      'Too many location choice requests.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

Map<String, dynamic> _locationResponse(List<dynamic> regions) => {
  'regions': regions,
  'provinces': <dynamic>[
    {'value': 'Laguna', 'label': 'Laguna'},
  ],
  'cities': <dynamic>[
    {'value': 'San Pablo City', 'label': 'San Pablo City'},
  ],
  'barangays': <dynamic>[
    {'value': 'San Rafael', 'label': 'San Rafael'},
  ],
  'resolved': {'region': '0400000000'},
};

void main() {
  testWidgets('location choices honor Retry-After before another read', (
    tester,
  ) async {
    final session = _RateLimitedLocationSession();
    final repository = BuyerRepository(session);
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: LocationPicker(
            repository: repository,
            initial: const {},
            onChanged: (_) {},
            onLoading: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.requests, hasLength(1));
    expect(find.textContaining('Try again in '), findsOneWidget);
    final retry = find.byType(TextButton).first;
    expect(tester.widget<TextButton>(retry).onPressed, isNull);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(session.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('selected location labels remain visible at text scale $scale', (
      tester,
    ) async {
      final repository = FakeBuyerRepository();
      addTearDown(repository.session.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Form(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LocationPicker(
                    repository: repository,
                    initial: const {
                      'region': '0400000000',
                      'province': 'Laguna',
                      'city': 'San Pablo City',
                      'barangay': 'San Rafael',
                    },
                    onChanged: (_) {},
                    onLoading: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'CALABARZON',
        'Laguna',
        'San Pablo City',
        'San Rafael',
      ]) {
        final value = find.text(label);
        expect(value, findsOneWidget);
        await Scrollable.ensureVisible(tester.element(value), alignment: .5);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(
          find.ancestor(of: value, matching: find.byType(IndexedStack)).first,
        );
        final text = tester.getRect(value);
        final paragraph = tester.renderObject<RenderParagraph>(value);
        final naturalText = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: text.width);
        try {
          expect(
            text.height,
            greaterThanOrEqualTo(naturalText.height - .1),
            reason:
                '$label must have enough height to paint its complete text.',
          );
        } finally {
          naturalText.dispose();
        }
        expect(
          text.top,
          greaterThanOrEqualTo(viewport.top - .1),
          reason: '$label must start inside its selected-value viewport.',
        );
        expect(
          text.bottom,
          lessThanOrEqualTo(viewport.bottom + .1),
          reason:
              '$label must be fully readable inside its selected-value viewport.',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, regions) in [
    (
      'duplicate location values',
      [
        {'value': '0400000000', 'label': 'CALABARZON'},
        {'value': '0400000000', 'label': 'Duplicate CALABARZON'},
      ],
    ),
    (
      'missing location labels',
      [
        {'value': '0400000000'},
      ],
    ),
  ]) {
    testWidgets('$name are recoverable instead of crashing the picker', (
      tester,
    ) async {
      final session = _LocationResponseSession(_locationResponse(regions));
      final repository = BuyerRepository(session);
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: LocationPicker(
              repository: repository,
              initial: const {'region': '0400000000'},
              onChanged: (_) {},
              onLoading: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Location choices are unavailable.'), findsOneWidget);
      expect(find.text('CALABARZON'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, response) in [
    (
      'location option map keys',
      _locationResponse([
        <dynamic, dynamic>{
          'value': '0400000000',
          'label': 'CALABARZON',
          7: 'unexpected',
        },
      ]),
    ),
    (
      'resolved location map keys',
      _locationResponse([
          {'value': '0400000000', 'label': 'CALABARZON'},
        ])
        ..['resolved'] = <dynamic, dynamic>{
          'region': '0400000000',
          7: 'unexpected',
        },
    ),
  ]) {
    testWidgets('$name fail closed without crashing the picker', (
      tester,
    ) async {
      final session = _LocationResponseSession(response);
      final repository = BuyerRepository(session);
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: LocationPicker(
              repository: repository,
              initial: const {'region': '0400000000'},
              onChanged: (_) {},
              onLoading: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Location choices are unavailable.'), findsOneWidget);
      expect(find.text('CALABARZON'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
