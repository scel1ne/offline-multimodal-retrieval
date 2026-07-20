import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/app/retrieval_app.dart';

void main() {
  testWidgets('app renders library and search panels', (tester) async {
    await tester.pumpWidget(const RetrievalApp());

    expect(find.text('Celine Retrieval'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsWidgets);
  });
}
