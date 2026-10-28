import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  test(
    'real submissions invalidate pending catalogue coalescing without replay',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final session = WebSession(Uri.parse('http://localhost:${server.port}'));
      addTearDown(() async {
        session.close();
        await server.close(force: true);
      });
      final repo = BuyerRepository(session);
      var reads = 0, posts = 0;
      final firstArrived = Completer<void>();
      final finishFirst = Completer<void>();
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.cookies.add(
          Cookie('XSRF-TOKEN', 'isolated')..path = '/',
        );
        if (request.method == 'POST') {
          posts++;
          request.response.write(jsonEncode({'saved': true, 'product_id': 1}));
        } else {
          reads++;
          if (reads == 2) {
            firstArrived.complete();
            await finishFirst.future;
          }
          request.response.write(
            jsonEncode({'component': 'Buyer/Home', 'props': homePage().props}),
          );
        }
        await request.response.close();
      });
      // Establish CSRF before the read being raced.
      await repo.home();
      final old = repo.home();
      final rejected = expectLater(
        old,
        throwsA(isA<BackendException>().having((e) => e.status, 'status', 409)),
      );
      await firstArrived.future;
      await repo.saveProduct(1, true);
      expect((await repo.home()).isCached, isFalse);
      expect(reads, 3);
      expect(posts, 1);
      finishFirst.complete();
      await rejected;
      expect(posts, 1);
    },
  );
}
