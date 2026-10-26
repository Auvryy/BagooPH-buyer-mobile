import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with the BagooPH Buyer app shell', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('BagooPH Buyer'), findsOneWidget);
  });
}
