import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../chat/chat_models.dart';
import '../chat/chat_orchestrator.dart';
import '../chat/chat_session_store.dart';
import '../core/models.dart';
import '../services/knowledge_engine.dart';
import 'microscope/retrieval_trace_page.dart';
import 'microscope/rag_lineage_dashboard_page.dart';

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
  List<KnowledgeDocument> documents = const [];
  bool loading = true;
  bool sending = false;
  bool attaching = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await widget.store.initialize();
      final sessions = await widget.store.listSessions();
      final current = sessions.isEmpty
          ? await widget.orchestrator.newSession()
          : sessions.first;
      final history = await widget.store.messages(current.id);
      final docs = await widget.engine.listDocuments();
      if (!mounted) return;
      setState(() {
        session = current;
        messages = history;
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
    final docs =
        reloadDocuments ? await widget.engine.listDocuments() : documents;
    if (!mounted) return;
    setState(() {
      session = loaded ?? current;
      messages = history;
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
      error = null;
    });
  }

  Future<void> _showHistory() async {
    final sessions = await widget.store.listSessions();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '会话历史',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in sessions)
                    ListTile(
                      selected: item.id == session?.id,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_modeLabel(item.mode)} · ${_scopeLabel(item.scope)}',
                      ),
                      onTap: () async {
                        final loaded = await widget.store.getSession(item.id);
                        final history = await widget.store.messages(item.id);
                        if (!mounted) return;
                        setState(() {
                          session = loaded ?? item;
                          messages = history;
                          error = null;
                        });
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                        _jumpToBottom();
                      },
                      trailing: IconButton(
                        tooltip: '删除会话',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await widget.store.deleteSession(item.id);
                          if (item.id == session?.id) {
                            final created =
                                await widget.orchestrator.newSession();
                            if (!mounted) return;
                            setState(() {
                              session = created;
                              messages = const [];
                            });
                          }
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocalState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    '知识库范围',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('全部知识库，或只外挂指定文档。'),
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
                    onPressed: () => Navigator.of(sheetContext).pop(
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

  Future<void> _attachFiles() async {
    final current = session;
    if (current == null || sending || attaching) return;
    setState(() {
      attaching = true;
      error = null;
    });
    try {
      final paths = await widget.engine.importer.pickDocumentPaths();
      if (paths.isEmpty) return;

      final selectedIds = <String>{...?current.scope.documentIds};
      final importedDocs = <ImportedDocument>[];
      final failedFiles = <String>[];
      for (final path in paths) {
        try {
          final doc = await widget.engine.importPath(path);
          importedDocs.add(doc);
          selectedIds.add(doc.documentId);
        } catch (e) {
          failedFiles.add('${_fileName(path)}: $e');
        }
      }

      if (importedDocs.isEmpty) {
        if (!mounted) return;
        setState(() => error = '附件导入失败：${failedFiles.join('；')}');
        return;
      }

      var updated = current;
      if (current.mode == ChatMode.modelOnly) {
        updated = await widget.orchestrator.setMode(current.id, ChatMode.auto);
      }
      updated = await widget.orchestrator.setScope(
        updated.id,
        KnowledgeScope.documents(selectedIds),
      );
      final docs = await widget.engine.listDocuments();
      if (!mounted) return;

      final textless = importedDocs.where((doc) => doc.chunks.isEmpty).length;
      setState(() {
        session = updated;
        documents = docs;
      });
      var message = '附件已加入知识库并绑定当前聊天 · ${importedDocs.length} 个';
      if (textless > 0) {
        message += ' · $textless 个文件未提取到可检索文本';
      }
      if (failedFiles.isNotEmpty) {
        message += ' · ${failedFiles.length} 个文件导入失败';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => attaching = false);
    }
  }

  Future<void> _detachDocument(String documentId) async {
    final current = session;
    if (current == null || current.scope.isAll || sending || attaching) return;
    final selectedIds = <String>{...?current.scope.documentIds};
    if (!selectedIds.remove(documentId)) return;
    final updated = await widget.orchestrator.setScope(
      current.id,
      KnowledgeScope.documents(selectedIds),
    );
    if (!mounted) return;
    setState(() => session = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已解除当前聊天附件；文件仍保留在知识库')),
    );
  }

  Future<void> _showTrace(ChatMessage message) async {
    final traceId = message.traceId;
    if (traceId == null) return;
    final lineageStore = widget.orchestrator.lineageStore;
    if (lineageStore != null) {
      final lineageTrace = await lineageStore.traceById(traceId);
      if (!mounted) return;
      if (lineageTrace != null) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RagLineageDashboardPage(
            engine: widget.engine,
            lineageStore: lineageStore,
            traceId: traceId,
            orchestrator: widget.orchestrator,
          ),
        ));
        return;
      }
    }
    final traceStore = widget.orchestrator.traceStore;
    if (traceStore == null) return;
    final trace = await traceStore.get(traceId);
    if (!mounted) return;
    if (trace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该历史回答没有可读取的 Trace。')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RetrievalTracePage(trace: trace, engine: widget.engine),
    ));
  }

  List<KnowledgeDocument> _boundDocuments(KnowledgeScope scope) {
    final ids = scope.documentIds;
    if (ids == null) return const <KnowledgeDocument>[];
    return documents.where((doc) => ids.contains(doc.documentId)).toList();
  }

  String _fileName(String path) {
    final segments = Uri.file(path).pathSegments;
    return segments.isEmpty ? path : segments.last;
  }

  Future<void> _send() async {
    final current = session;
    final text = input.text.trim();
    if (current == null || text.isEmpty || sending || attaching) return;
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
              Text(
                '[${evidence.anchor}] ${evidence.chunk.sourceName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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

  String _retrievalRouteLabel(String mode) {
    if (mode.startsWith('modelOnly')) return '本机模型';
    if (mode == 'auto:modelOnly') return 'Auto → Model';
    if (mode.startsWith('auto:')) return 'Auto → Knowledge';
    return 'Knowledge ON';
  }

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
    if (current == null) return Center(child: Text(error ?? '无法创建聊天会话'));
    final boundDocuments = _boundDocuments(current.scope);
    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          IconButton(
            tooltip: '新建会话',
            onPressed: sending || attaching ? null : _newSession,
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
                      Text(
                        FlutterGemma.hasActiveModel()
                            ? 'Gemma READY'
                            : 'Gemma 准备中',
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: sending || attaching ? null : _selectScope,
                        icon: const Icon(Icons.library_books_outlined, size: 18),
                        label: Text(_scopeLabel(current.scope)),
                      ),
                    ],
                  ),
                  SegmentedButton<ChatMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ChatMode.modelOnly,
                        label: Text('纯模型'),
                      ),
                      ButtonSegment(value: ChatMode.auto, label: Text('自动')),
                      ButtonSegment(
                        value: ChatMode.knowledge,
                        label: Text('强制知识库'),
                      ),
                    ],
                    selected: {current.mode},
                    onSelectionChanged: sending || attaching
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) =>
                          _messageBubble(messages[index]),
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (boundDocuments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final doc in boundDocuments)
                        InputChip(
                          avatar: const Icon(Icons.attach_file, size: 16),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              doc.sourceName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onDeleted: sending || attaching
                              ? null
                              : () => _detachDocument(doc.documentId),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    tooltip: '上传文件',
                    onPressed: sending || attaching ? null : _attachFiles,
                    icon: attaching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
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
                    onPressed: sending || attaching ? null : _send,
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
            Text(
              'PocketGallery',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: message.retrievalMode!,
                    child: Text(
                      _retrievalRouteLabel(message.retrievalMode!),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (message.traceId != null &&
                      (widget.orchestrator.lineageStore != null ||
                          widget.orchestrator.traceStore != null)) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: () => _showTrace(message),
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: const Text('检索依据'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
