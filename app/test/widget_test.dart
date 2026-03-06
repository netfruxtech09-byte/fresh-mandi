import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_mandi_app/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const FreshMandiApp());
    expect(find.text('Fresh Mandi'), findsOneWidget);
  });
}
