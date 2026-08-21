package com.google.ai.edge.gallery.pocketgallery.knowledge.store

import com.google.ai.edge.gallery.pocketgallery.knowledge.db.KnowledgeChunkEntity
import com.google.ai.edge.gallery.pocketgallery.knowledge.db.KnowledgeDao
import com.google.ai.edge.gallery.pocketgallery.knowledge.db.KnowledgeDocumentEntity
import com.google.ai.edge.gallery.pocketgallery.knowledge.db.KnowledgeSearchRow
import com.google.ai.edge.gallery.pocketgallery.knowledge.model.KnowledgeChunk

class RoomKnowledgeStore(
  private val dao: KnowledgeDao,
) : KnowledgeStore {
  override suspend fun findDocumentIdBySha256(sha256: String): String? =
    dao.findDocumentIdBySha256(sha256)

  override suspend fun insertDocumentWithChunks(
    document: KnowledgeDocumentRecord,
    chunks: List<KnowledgeChunk>,
  ) {
    dao.insertDocumentWithChunks(
      document = document.toEntity(),
      chunks = chunks.map { it.toEntity(document.documentId) },
    )
  }

  override suspend fun searchFts(matchQuery: String, limit: Int): List<KnowledgeSearchHit> =
    dao.searchFts(matchQuery, limit).map(KnowledgeSearchRow::toDomain)

  override suspend fun searchLike(escapedNeedle: String, limit: Int): List<KnowledgeSearchHit> =
    dao.searchLike(escapedNeedle, limit).map(KnowledgeSearchRow::toDomain)

  private fun KnowledgeDocumentRecord.toEntity(): KnowledgeDocumentEntity =
    KnowledgeDocumentEntity(
      documentId = documentId,
      sourceUri = sourceUri,
      displayName = displayName,
      mimeType = mimeType,
      sha256 = sha256,
      sizeBytes = sizeBytes,
      importedAtEpochMs = importedAtEpochMs,
      modifiedAtEpochMs = modifiedAtEpochMs,
      parseStatus = parseStatus,
      parseError = parseError,
    )

  private fun KnowledgeChunk.toEntity(documentId: String): KnowledgeChunkEntity =
    KnowledgeChunkEntity(
      chunkId = chunkId,
      documentId = documentId,
      ordinal = ordinal,
      pageOrSection = pageOrSection,
      text = text,
      charStart = charStart,
      charEnd = charEnd,
      tokenEstimate = tokenEstimate,
    )

  private fun KnowledgeSearchRow.toDomain(): KnowledgeSearchHit =
    KnowledgeSearchHit(
      chunkId = chunkId,
      documentId = documentId,
      displayName = displayName,
      sourceUri = sourceUri,
      ordinal = ordinal,
      pageOrSection = pageOrSection,
      text = text,
      score = null,
    )
}
