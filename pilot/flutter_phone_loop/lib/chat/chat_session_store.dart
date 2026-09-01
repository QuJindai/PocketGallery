import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'chat_models.dart';

class ChatSessionStore {
  ChatSessionStore({Database? database})
    : _db = database,
      _ownsDatabase = database == null;

  Database? _db;
  final bool _ownsDatabase;
  int _idCounter = 0;

  Future<void> initialize() async {
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      _db = sqlite3.open(File(p.join(dir.path, 'pocketgallery_chat.db')).path);
    }
    final db = _db!;
    db.execute('PRAGMA foreign_keys=ON;');
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions (
        session_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        mode TEXT NOT NULL,
        knowledge_scope_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        message_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retrieval_mode TEXT,
        evidence_json TEXT,
        cited_anchors_json TEXT,
        trace_id TEXT,
        FOREIGN KEY(session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
      );
    ''');
    final columns = db
        .select('PRAGMA table_info(chat_messages)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('trace_id')) {
      db.execute('ALTER TABLE chat_messages ADD COLUMN trace_id TEXT;');
    }
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_messages_session_time
      ON chat_messages(session_id, created_at);
    ''');
  }

  String nextMessageId() => _nextId('m');

  Future<ChatSession> createSession({
    String title = '新会话',
    ChatMode mode = ChatMode.auto,
    KnowledgeScope scope = const KnowledgeScope.all(),
  }) async {
    await initialize();
    final now = DateTime.now();
    final session = ChatSession(
      id: _nextId('s'),
      title: title,
      mode: mode,
      scope: scope,
      createdAt: now,
      updatedAt: now,
    );
    _db!.execute(
      '''
      INSERT INTO chat_sessions
      (session_id, title, mode, knowledge_scope_json, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    ''',
      [
        session.id,
        session.title,
        session.mode.name,
        session.scope.toJson(),
        session.createdAt.toIso8601String(),
        session.updatedAt.toIso8601String(),
      ],
    );
    return session;
  }

  Future<List<ChatSession>> listSessions() async {
    await initialize();
    final rows = _db!.select('''
      SELECT session_id, title, mode, knowledge_scope_json, created_at, updated_at
      FROM chat_sessions
      ORDER BY updated_at DESC
    ''');
    return rows.map(_rowToSession).toList();
  }

  Future<ChatSession?> getSession(String sessionId) async {
    await initialize();
    final rows = _db!.select(
      '''
      SELECT session_id, title, mode, knowledge_scope_json, created_at, updated_at
      FROM chat_sessions WHERE session_id = ? LIMIT 1
    ''',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return _rowToSession(rows.first);
  }

  Future<ChatSession> updateSession(
    String sessionId, {
    String? title,
    ChatMode? mode,
    KnowledgeScope? scope,
  }) async {
    final current = await getSession(sessionId);
    if (current == null) throw StateError('Unknown chat session: $sessionId');
    final updated = current.copyWith(
      title: title,
      mode: mode,
      scope: scope,
      updatedAt: DateTime.now(),
    );
    _db!.execute(
      '''
      UPDATE chat_sessions
      SET title = ?, mode = ?, knowledge_scope_json = ?, updated_at = ?
      WHERE session_id = ?
    ''',
      [
        updated.title,
        updated.mode.name,
        updated.scope.toJson(),
        updated.updatedAt.toIso8601String(),
        updated.id,
      ],
    );
    return updated;
  }

  Future<void> appendMessage(ChatMessage message) async {
    await initialize();
    _db!.execute(
      '''
      INSERT INTO chat_messages
      (message_id, session_id, role, text, created_at,
       retrieval_mode, evidence_json, cited_anchors_json, trace_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        message.id,
        message.sessionId,
        message.role.name,
        message.text,
        message.createdAt.toIso8601String(),
        message.retrievalMode,
        message.evidenceJson,
        message.citedAnchorsJson,
        message.traceId,
      ],
    );
    _db!.execute(
      'UPDATE chat_sessions SET updated_at = ? WHERE session_id = ?',
      [DateTime.now().toIso8601String(), message.sessionId],
    );
  }

  Future<List<ChatMessage>> messages(String sessionId) async {
    await initialize();
    final rows = _db!.select(
      '''
      SELECT message_id, session_id, role, text, created_at,
             retrieval_mode, evidence_json, cited_anchors_json, trace_id
      FROM chat_messages
      WHERE session_id = ?
      ORDER BY created_at, rowid
    ''',
      [sessionId],
    );
    return rows.map(_rowToMessage).toList();
  }

  Future<void> clearMessages(String sessionId) async {
    await initialize();
    _db!.execute('DELETE FROM chat_messages WHERE session_id = ?', [sessionId]);
    _db!.execute(
      'UPDATE chat_sessions SET updated_at = ? WHERE session_id = ?',
      [DateTime.now().toIso8601String(), sessionId],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await initialize();
    _db!.execute('DELETE FROM chat_sessions WHERE session_id = ?', [sessionId]);
  }

  ChatSession _rowToSession(Row row) {
    final modeName = row['mode'] as String;
    final mode = ChatMode.values.firstWhere(
      (x) => x.name == modeName,
      orElse: () => ChatMode.auto,
    );
    return ChatSession(
      id: row['session_id'] as String,
      title: row['title'] as String,
      mode: mode,
      scope: KnowledgeScope.fromJson(row['knowledge_scope_json'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  ChatMessage _rowToMessage(Row row) => ChatMessage(
    id: row['message_id'] as String,
    sessionId: row['session_id'] as String,
    role: (row['role'] as String) == ChatRole.assistant.name
        ? ChatRole.assistant
        : ChatRole.user,
    text: row['text'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    retrievalMode: row['retrieval_mode'] as String?,
    evidenceJson: row['evidence_json'] as String?,
    citedAnchorsJson: row['cited_anchors_json'] as String?,
    traceId: row['trace_id'] as String?,
  );

  String _nextId(String prefix) {
    _idCounter++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  void close() {
    if (_ownsDatabase) _db?.close();
    _db = null;
  }
}
