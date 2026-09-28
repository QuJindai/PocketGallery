package com.google.ai.edge.gallery.pocketgallery.knowledge.intake

import com.google.ai.edge.gallery.pocketgallery.knowledge.chunk.DocumentChunker
import com.google.ai.edge.gallery.pocketgallery.knowledge.hash.Sha256
import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.ParserRegistry
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.UnsupportedDocumentTypeException
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeDocumentRecord
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeStore

enum class IngestFailureCode {
  UNSUPPORTED_DOCUMENT_TYPE,
}

sealed interface IngestResult {
  data class Imported(
    val documentId: String,
    val chunkCount: Int,
  ) : IngestResult

  data class Duplicate(
    val existingDocumentId: String,
  ) : IngestResult

  data class Failed(
    val code: IngestFailureCode,
    val message: String,
  ) : IngestResult
}

class KnowledgeIngestor(
  private val store: KnowledgeStore,
  private val parserRegistry: ParserRegistry = ParserRegistry(),
  private val chunker: DocumentChunker = DocumentChunker(),
  private val nowEpochMs: () -> Long = { System.currentTimeMillis() },
) {
  suspend fun ingest(input: DocumentInput): IngestResult {
    val sha256 = Sha256.hex(input.bytes)
    store.findDocumentIdBySha256(sha256)?.let { existingDocumentId ->
      return IngestResult.Duplicate(existingDocumentId)
    }

    val normalized = try {
      parserRegistry.parse(input)
    } catch (error: UnsupportedDocumentTypeException) {
      return IngestResult.Failed(
        code = IngestFailureCode.UNSUPPORTED_DOCUMENT_TYPE,
        message = error.message ?: "Unsupported document type",
      )
    }

    val chunks = chunker.chunk(sha256, normalized)
    val document = KnowledgeDocumentRecord(
      documentId = sha256,
      sourceUri = input.sourceUri,
      displayName = input.displayName,
      mimeType = input.mimeType,
      sha256 = sha256,
      sizeBytes = input.bytes.size.toLong(),
      importedAtEpochMs = nowEpochMs(),
      modifiedAtEpochMs = input.modifiedAtEpochMs,
    )
    store.insertDocumentWithChunks(document, chunks)
    return IngestResult.Imported(documentId = sha256, chunkCount = chunks.size)
  }
}
