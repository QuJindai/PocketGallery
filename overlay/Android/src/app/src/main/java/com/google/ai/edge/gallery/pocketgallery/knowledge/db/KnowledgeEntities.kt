package com.google.ai.edge.gallery.pocketgallery.knowledge.db

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Fts5
import androidx.room3.FtsOptions
import androidx.room3.Index
import androidx.room3.PrimaryKey

@Entity(
  tableName = "knowledge_documents",
  indices = [Index(value = ["sha256"], unique = true)],
)
data class KnowledgeDocumentEntity(
  @PrimaryKey val documentId: String,
  val sourceUri: String,
  val displayName: String,
  val mimeType: String,
  val sha256: String,
  val sizeBytes: Long,
  val importedAtEpochMs: Long,
  val modifiedAtEpochMs: Long?,
  val parseStatus: String,
  val parseError: String?,
)

@Entity(
  tableName = "knowledge_chunks",
  foreignKeys = [
    ForeignKey(
      entity = KnowledgeDocumentEntity::class,
      parentColumns = ["documentId"],
      childColumns = ["documentId"],
      onDelete = ForeignKey.CASCADE,
    ),
  ],
  indices = [
    Index(value = ["documentId"]),
    Index(value = ["chunkId"], unique = true),
  ],
)
data class KnowledgeChunkEntity(
  @PrimaryKey(autoGenerate = true)
  @ColumnInfo(name = "rowid")
  val rowId: Long = 0,
  val chunkId: String,
  val documentId: String,
  val ordinal: Int,
  val pageOrSection: String?,
  val text: String,
  val charStart: Int,
  val charEnd: Int,
  val tokenEstimate: Int,
)

@Entity(tableName = "knowledge_chunks_fts")
@Fts5(
  contentEntity = KnowledgeChunkEntity::class,
  contentRowId = "rowid",
  tokenizer = FtsOptions.TOKENIZER_TRIGRAM,
)
data class KnowledgeChunkFts(
  val text: String,
)

data class KnowledgeSearchRow(
  val chunkId: String,
  val documentId: String,
  val displayName: String,
  val sourceUri: String,
  val ordinal: Int,
  val pageOrSection: String?,
  val text: String,
)
