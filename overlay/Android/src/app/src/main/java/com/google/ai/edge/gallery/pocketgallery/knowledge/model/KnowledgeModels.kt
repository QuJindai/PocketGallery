package com.google.ai.edge.gallery.pocketgallery.knowledge.model

data class DocumentInput(
  val sourceUri: String,
  val displayName: String,
  val mimeType: String,
  val bytes: ByteArray,
  val modifiedAtEpochMs: Long? = null,
)

data class KnowledgeChunk(
  val chunkId: String,
  val ordinal: Int,
  val pageOrSection: String?,
  val text: String,
  val charStart: Int,
  val charEnd: Int,
  val tokenEstimate: Int,
)
