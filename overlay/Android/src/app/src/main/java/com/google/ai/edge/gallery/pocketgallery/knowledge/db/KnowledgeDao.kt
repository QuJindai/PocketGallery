package com.google.ai.edge.gallery.pocketgallery.knowledge.db

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query
import androidx.room3.Transaction

@Dao
abstract class KnowledgeDao {
  @Insert
  abstract suspend fun insertDocument(document: KnowledgeDocumentEntity)

  @Insert
  abstract suspend fun insertChunks(chunks: List<KnowledgeChunkEntity>)

  @Transaction
  open suspend fun insertDocumentWithChunks(
    document: KnowledgeDocumentEntity,
    chunks: List<KnowledgeChunkEntity>,
  ) {
    insertDocument(document)
    if (chunks.isNotEmpty()) insertChunks(chunks)
  }

  @Query("SELECT documentId FROM knowledge_documents WHERE sha256 = :sha256 LIMIT 1")
  abstract suspend fun findDocumentIdBySha256(sha256: String): String?

  @Query("DELETE FROM knowledge_documents WHERE documentId = :documentId")
  abstract suspend fun deleteDocument(documentId: String)

  @Query(
    """
    SELECT c.chunkId, c.documentId, d.displayName, d.sourceUri,
           c.ordinal, c.pageOrSection, c.text
    FROM knowledge_chunks_fts
    JOIN knowledge_chunks AS c ON c.rowid = knowledge_chunks_fts.rowid
    JOIN knowledge_documents AS d ON d.documentId = c.documentId
    WHERE knowledge_chunks_fts MATCH :matchQuery
    ORDER BY c.ordinal
    LIMIT :limit
    """,
  )
  abstract suspend fun searchFts(matchQuery: String, limit: Int): List<KnowledgeSearchRow>

  @Query(
    """
    SELECT c.chunkId, c.documentId, d.displayName, d.sourceUri,
           c.ordinal, c.pageOrSection, c.text
    FROM knowledge_chunks AS c
    JOIN knowledge_documents AS d ON d.documentId = c.documentId
    WHERE c.text LIKE '%' || :escapedNeedle || '%' ESCAPE '\'
    ORDER BY c.ordinal
    LIMIT :limit
    """,
  )
  abstract suspend fun searchLike(escapedNeedle: String, limit: Int): List<KnowledgeSearchRow>
}
