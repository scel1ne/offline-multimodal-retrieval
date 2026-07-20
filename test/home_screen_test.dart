import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/embedding/tflite_embedding_engine.dart';
import 'package:offline_accessible_retrieval/src/parsing/local_content_parser.dart';
import 'package:offline_accessible_retrieval/src/retrieval/retrieval_service.dart';
import 'package:offline_accessible_retrieval/src/storage/chroma_vector_store.dart';
import 'package:offline_accessible_retrieval/src/ui/home_screen.dart';

void main() {
  testWidgets('renders usable local library and search controls',
      (tester) async {
    final service = _HomeScreenService();
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(retrievalService: service)),
    );

    // Library panel labels.
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Choose files'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('No files indexed yet.'), findsOneWidget);

    // Search panel labels.
    expect(find.text('Search'), findsWidgets);

    // Switch the dark/light theme and drag the font slider.
    final themeButton = find.byIcon(Icons.dark_mode_rounded);
    expect(themeButton, findsOneWidget);
    await tester.tap(themeButton);
    await tester.pump();
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pump();

    // Type a query and submit.
    await tester.enterText(find.byType(TextField), 'offline notes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Search'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pump();

    // No indexed files -> empty state.
    expect(find.text('Add files to start searching.'), findsOneWidget);
  });
}

class _HomeScreenService extends RetrievalService {
  _HomeScreenService()
      : super(
          parser: LocalContentParser(),
          embeddingEngine: TfliteEmbeddingEngine(),
          vectorStore: ChromaVectorStore(),
        );
}
