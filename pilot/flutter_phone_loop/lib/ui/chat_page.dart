import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../chat/chat_orchestrator.dart';
import '../chat/chat_session_store.dart';
import '../core/models.dart';
import '../services/knowledge_engine.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.engine,
    required this.store,
    required this.orchestrator,
  });

  final KnowledgeEngine engine;
  final ChatSessionStore store;
  final ChatOrchestrator orchestrator;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();

  ChatSession? session;
  List<ChatMessage> messages = const [];
  List<ChatSession> sessions = const [];
  List<KnowledgeDocument> documents = const [];
  bool loading = true;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await widget.store.initialize();
      final existing = await widget.store.listSessions();
      final docs = await widget.engine.listDocuments();
      final current = existing.isEmpty
          ? await widget.orchestrator.newSession()
          : existing.first;
      final loadedMessages = await widget.store.messages(current.id);
      if (!mounted) return;
      setState(() {
        session = current;
        sessions = existing.isEmpty ? [current] : existing;
        messages = loadedMessages;
        documents = docs;
        loading = false;
      });
      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> _reload({bool reloadDocuments = false}) async {
    final current = session;
    if (current == null) return;
    final loaded = await widget.store.getSession(current.id);
    final history = await widget.store.messages(current.id);
    final allSessions = await widget.store.listSessions();
    final docs = reloadDocuments ? await widget.engine.listDocuments() : documents;
    if (!mounted) return;
    setState(() {
      session = loaded ?? current;
      messages = history;
      sessions = allSessions;
      documents = docs;
    });
    _jumpToBottom();
  }

  Future<void> _newSession() async {
    final created = await widget.orchestrator.newSession();
    if (!mounted) return;
    setState(() {
      session = created;
      messages = const [];
      sessions = [created, ...sessions];
      error = null;
    });
  }

  Future<void> _selectSession(ChatSession selected) async {
    final loaded = await widget.store.getSession(selected.id);
    final history = await widget.store.messages(selected.id);
    if (!mounted) return;
    setState(() {
      session = loaded ?? selected;
      messages = history;
      error = null;
    });
    Navigator.of(context).maybePop();
    _jumpToBottom();
  }

  Future<void> _showHistory() async {
    final currentSessions = await widget.store.listSessions();
    if (!mounted) return;
    setState(() => sessions = currentSessions);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('会话历史', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in currentSessions)
                    ListTile(
                      selected: item.id == session?.id,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_modeLabel(item.mode)} · ${_scopeLabel(item.scope)}'),
                      onTap: () => _selectSession(item),
                      trailing: IconButton(
                        tooltip: '删除会话',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await widget.store.deleteSession(item.id);
                          if (item.id == session?.id) {
                            final created = await widget.orchestrator.newSession();
                            if (!mounted) return;
                            setState(() {
                              session = created;
                              messages = const [];
                            });
                          }
                          if (mounted) Navigator.of(context).pop();
                          await _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearSession() async {
    final current = session;
    if (current == null) return;
    await widget.orchestrator.clearSession(current.id);
    if (!mounted) return;
    setState(() {
      messages = const [];
      error = null;
    });
  }

  Future<void> _setMode(ChatMode mode) async {
    final current = session;
    if (current == null) return;
    final updated = await widget.orchestrator.setMode(current.id, mode);
    if (!mounted) return;
    setState(() => session = updated);
  }

  Future<void> _selectScope() async {
    final current = session;
    if (current == null) return;
    final docs = await widget.engine.listDocuments();
    final selected = <String>{...?current.scope.documentIds};
    var all = current.scope.isAll;
    if (!mounted) return;

    final result = await showModalBottomSheet<KnowledgeScope>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              children: [
                const ListTile(
                  title: Text('知识库范围', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('可使用全部知识库，也可以只外挂指定文档。'),
                ),
                SwitchListTile(
                  title: const Text('全部知识库'),
                  value: all,
                  onChanged: (value) => setLocalState(() => all = value),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      for (final doc in docs)
                        CheckboxListTile(
                          enabled: !all,
                          value: all || selected.contains(doc.documentId),
                          title: Text(doc.sourceName),
                          subtitle: Text('${doc.chunkCount} chunks'),
                          onChanged: all
                              ? null
                              : (value) => setLocalState(() {
                                    if (value == true) {
                                      selected.add(doc.documentId);
                                    } else {
                                      selected.remove(doc.documentId);
                                    }
                                  }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      all
                          ? const KnowledgeScope.all()
                          : KnowledgeScope.documents(selected),
                    ),
                    child: const Text('应用范围'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null) return;
    final updated = await widget.orchestrator.setScope(current.id, result);
    if (!mounted) return;
    setState(() {
      session = updated;
      documents = docs;
    });
  }

  Future<void> _send() async {
    final current = session;
    final text = input.text.trim();
    if (current == null || text.isEmpty || sending) return;
    if (!FlutterGemma.hasActiveModel()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemma 4 模型准备中，请在“模型 / 设置”中查看状态。')),
      );
      return;
    }

    setState(() {
      sending = true;
      error = null;
      input.clear();
      messages = [
        ...messages,
        ChatMessage.user(
          id: 'optimistic_${DateTime.now().microsecondsSinceEpoch}',
          sessionId: current.id,
          text: text,
        ),
      ];
    });
    _jumpToBottom();

    try {
      await widget.orchestrator.sendMessage(current.id, text);
      await _reload(reloadDocuments: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
      await _reload();
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _showEvidence(EvidenceItem evidence) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('[${evidence.anchor}] ${evidence.chunk.sourceName}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(evidence.chunk.locator),
              const Divider(),
              SelectableText(evidence.chunk.text),
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(ChatMode mode) => switch (mode) {
        ChatMode.modelOnly => '纯模型',
        ChatMode.auto => '自动',
        ChatMode.knowledge => '强制知识库',
      };

  String _scopeLabel(KnowledgeScope scope) => scope.isAll
      ? '全部知识库'
      : '指定文档 ${scope.documentIds?.length ?? 0}';

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (current == null) {
      return Center(child: Text(error ?? '无法创建聊天会话'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          IconButton(
            tooltip: '新建会话',
            onPressed: sending ? null : _newSession,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: '会话历史',
            onPressed: _showHistory,
            icon: const Icon(Icons.history),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clearSession();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('清空当前会话')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        FlutterGemma.hasActiveModel()
                            ? Icons.check_circle_outline
                            : Icons.downloading_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(FlutterGemma.hasActiveModel()
                          ? 'Gemma READY'
                          : 'Gemma 准备中'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _selectScope,
                        icon: const Icon(Icons.library_books_outlined, size: 18),
                        label: Text(_scopeLabel(current.scope)),
                      ),
                    ],
                  ),
                  SegmentedButton<ChatMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ChatMode.modelOnly, label: Text('纯模型')),
                      ButtonSegment(value: ChatMode.auto, label: Text('自动')),
                      ButtonSegment(value: ChatMode.knowledge, label: Text('强制知识库')),
                    ],
                    selected: {current.mode},
                    onSelectionChanged: sending
                        ? null
                        : (value) => _setMode(value.first),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: messages.isEmpty
                  ? _emptyState(current.mode)
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => _messageBubble(messages[index]),
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: current.mode == ChatMode.modelOnly
                            ? '直接和本机模型聊天…'
                            : current.mode == ChatMode.auto
                                ? '聊天；需要时自动外挂本地知识库…'
                                : '基于本地知识库提问…',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: sending ? null : _send,
                    icon: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ChatMode mode) {
    final text = switch (mode) {
      ChatMode.modelOnly => '直接和 Gemma 4 多轮聊天，不使用知识库。',
      ChatMode.auto => '直接聊天。涉及本地资料时，PocketGallery 会自动外挂知识库。',
      ChatMode.knowledge => '回答必须基于本地知识库；没有证据时会明确提示资料不足。',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 48),
            const SizedBox(height: 12),
            Text('PocketGallery', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(ChatMessage message) {
    final user = message.role == ChatRole.user;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message.text),
            if (!user && message.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final item in message.evidence)
                    ActionChip(
                      label: Text('[${item.anchor}]'),
                      onPressed: () => _showEvidence(item),
                    ),
                ],
              ),
            ],
            if (!user && message.retrievalMode != null) ...[
              const SizedBox(height: 4),
              Text(
                message.retrievalMode!.startsWith('modelOnly') ||
                        message.retrievalMode == 'auto:modelOnly'
                    ? '本机模型'
                    : 'Knowledge ON',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
