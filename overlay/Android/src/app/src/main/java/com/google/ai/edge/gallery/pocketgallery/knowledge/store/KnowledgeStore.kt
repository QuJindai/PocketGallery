package com.google.ai.edge.gallery.pocketgallery.knowledge.store

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.KnowledgeChunk

data class KnowledgeDocumentRecord(
  val documentId: String,
  val sourceUri: String,
  val displayName: String,
  val mimeType: String,
  val sha256: String,
  val sizeBytes: Long,
  val importedAtEpochMs: Long,
  val modifiedAtEpochMs: Long?,
  val parseStatus: String = "ready",
  val parseError: String? = null,
)

data class KnowledgeSearchHit(
  val chunkId: String,
  val documentId: String,
  val displayName: String,
  val sourceUri: String,
  val ordinal: Int,
  val pageOrSection: String?,
  val text: String,
  val score: Double? = null,
)

interface KnowledgeStore {
  suspend fun findDocumentIdBySha256(sha256: String): String?

  suspend fun insertDocumentWithChunks(
    document: KnowledgeDocumentRecord,
    chunks: List<KnowledgeChunk>,
  )

  suspend fun searchFts(matchQuery: String, limit: Int): List<KnowledgeSearchHit>

  suspend fun searchLike(escapedNeedle: String, limit: Int): List<KnowledgeSearchHit>
}
