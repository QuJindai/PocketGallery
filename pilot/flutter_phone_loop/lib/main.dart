import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

import 'services/knowledge_engine.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    embeddingBackends: [LiteRtEmbeddingBackend()],
    vectorStore: SqliteVectorStore(),
  );

  final engine = KnowledgeEngine();
  await engine.initialize();

  runApp(PocketGalleryPilot(engine: engine));
}

class PocketGalleryPilot extends StatelessWidget {
  const PocketGalleryPilot({super.key, required this.engine});
  final KnowledgeEngine engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketGallery Phone Pilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: HomePage(engine: engine),
    );
  }
}
