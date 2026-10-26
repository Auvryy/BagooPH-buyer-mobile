import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';

/// Read-only contract check; never registers, signs in, or sends email.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/check_backend.dart <BACKEND_ORIGIN>');
    exitCode = 64;
    return;
  }
  final session = WebSession(Uri.parse(args.single));
  final repository = BuyerRepository(session);
  try {
    final home = await repository.home();
    if (home.component != 'Buyer/Home' || home.props['feedProducts'] is! Map) {
      throw StateError('Expected Buyer/Home with a paginated feed.');
    }
    final registration = await repository.registration();
    final policies = mapOf(registration.props['policies']);
    if (registration.component != 'Auth/Register' ||
        policies['terms_url'] is! String ||
        mapOf(registration.props['birthDateLimits'])['adult_maximum']
            is! String) {
      throw StateError(
        'Expected the registration policy and birth-date contract.',
      );
    }
    final policy = await repository.document(policies['terms_url'] as String);
    if (mapOf(policy.props['document'])['sections'] is! List) {
      throw StateError('Expected a readable policy document.');
    }
    final filtered = await repository.home(
      search: 'backpack',
      sort: 'price_asc',
    );
    if (mapOf(filtered.props['filters'])['search'] != 'backpack') {
      throw StateError('The server did not retain the search filter.');
    }
    stdout.writeln(
      'Buyer home, registration, policies, and filtered catalogue contracts passed.',
    );
    stdout.writeln(
      '${mapsOf(home.props['categories']).length} categories; ${mapOf(home.props['feedProducts'])['total']} listings.',
    );
  } catch (error) {
    stderr.writeln('Backend contract check failed: $error');
    exitCode = 1;
  } finally {
    session.close();
  }
}
