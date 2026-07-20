import 'package:flutter/material.dart';

import '../embedding/tflite_embedding_engine.dart';
import '../parsing/local_content_parser.dart';
import '../retrieval/retrieval_service.dart';
import '../storage/chroma_vector_store.dart';
import '../ui/home_screen.dart';

class RetrievalApp extends StatelessWidget {
  const RetrievalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final parser = LocalContentParser();
    final embeddingEngine = TfliteEmbeddingEngine();
    final vectorStore = ChromaVectorStore();
    final retrievalService = RetrievalService(
      parser: parser,
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
    );

    return MaterialApp(
      title: 'Offline Local Retrieval',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff126b61)),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      highContrastTheme: ThemeData(
        colorScheme: const ColorScheme.highContrastLight(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Color(0xff005a52),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(retrievalService: retrievalService),
    );
  }
}
