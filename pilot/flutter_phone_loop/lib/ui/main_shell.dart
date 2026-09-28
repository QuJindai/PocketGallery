import 'package:flutter/material.dart';

import '../chat/chat_orchestrator.dart';
import '../chat/chat_session_store.dart';
import '../services/knowledge_engine.dart';
import 'chat_page.dart';
import 'knowledge_page.dart';
import 'model_settings_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.engine,
    required this.store,
    required this.orchestrator,
  });

  final KnowledgeEngine engine;
  final ChatSessionStore store;
  final ChatOrchestrator orchestrator;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          ChatPage(
            engine: widget.engine,
            store: widget.store,
            orchestrator: widget.orchestrator,
          ),
          KnowledgePage(
            engine: widget.engine,
            orchestrator: widget.orchestrator,
          ),
          ModelSettingsPage(engine: widget.engine, store: widget.store),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '聊天',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '知识库',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '模型 / 设置',
          ),
        ],
      ),
    );
  }
}
