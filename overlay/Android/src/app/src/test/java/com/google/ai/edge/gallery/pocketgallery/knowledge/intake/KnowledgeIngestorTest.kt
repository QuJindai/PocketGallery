package com.google.ai.edge.gallery.pocketgallery.knowledge.intake

import com.google.ai.edge.gallery.pocketgallery.knowledge.chunk.DocumentChunker
import com.google.ai.edge.gallery.pocketgallery.knowledge.hash.Sha256
import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput
import com.google.ai.edge.gallery.pocketgallery.knowledge.model.KnowledgeChunk
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.DocumentParser
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.NormalizedDocument
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.NormalizedSection
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.ParserRegistry
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeDocumentRecord
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeSearchHit
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KnowledgeIngestorTest {
  @Test
  fun importOrdersDedupeBeforeParseAndPersistsDeterministicChunks() = runBlocking {
    val events = mutableListOf<String>()
    val input = DocumentInput(
      sourceUri = "content://fixture/local.txt",
      displayName = "local.txt",
      mimeType = "text/plain",
      bytes = "local knowledge evidence".toByteArray(),
      modifiedAtEpochMs = 500,
    )
    val expectedSha = Sha256.hex(input.bytes)
    val store = RecordingStore(events)
    val parser = object : DocumentParser {
      override fun supports(input: DocumentInput) = true
      override fun parse(input: DocumentInput): NormalizedDocument {
        events += "parse"
        val text = input.bytes.toString(Charsets.UTF_8)
        return NormalizedDocument(text, listOf(NormalizedSection(null, text)))
      }
    }

    val result = KnowledgeIngestor(
      store = store,
      parserRegistry = ParserRegistry(listOf(parser)),
      chunker = DocumentChunker(maxChars = 1200, overlapChars = 150),
      nowEpochMs = { 1_000 },
    ).ingest(input)

    assertEquals(listOf("dedupe:$expectedSha", "parse", "persist"), events)
    assertEquals(IngestResult.Imported(expectedSha, 1), result)
    assertEquals(expectedSha, store.persistedDocument?.documentId)
    assertEquals(expectedSha, store.persistedDocument?.sha256)
    assertEquals(1_000, store.persistedDocument?.importedAtEpochMs)
    assertEquals(500, store.persistedDocument?.modifiedAtEpochMs)
    assertEquals(1, store.persistedChunks.size)
    assertEquals("local knowledge evidence", store.persistedChunks.single().text)
  }

  @Test
  fun duplicateStopsBeforeParsingOrPersistence() = runBlocking {
    val events = mutableListOf<String>()
    val store = RecordingStore(events, existingDocumentId = "existing-doc")
    val parser = object : DocumentParser {
      override fun supports(input: DocumentInput) = true
      override fun parse(input: DocumentInput): NormalizedDocument {
        error("duplicate input must not be parsed")
      }
    }
    val input = DocumentInput("content://duplicate", "duplicate.txt", "text/plain", "same".toByteArray())

    val result = KnowledgeIngestor(
      store = store,
      parserRegistry = ParserRegistry(listOf(parser)),
      nowEpochMs = { 1_000 },
    ).ingest(input)

    assertEquals(IngestResult.Duplicate("existing-doc"), result)
    assertEquals(listOf("dedupe:${Sha256.hex(input.bytes)}"), events)
    assertTrue(store.persistedChunks.isEmpty())
  }

  @Test
  fun unsupportedTypeReturnsTypedFailureWithoutPartialWrite() = runBlocking {
    val events = mutableListOf<String>()
    val store = RecordingStore(events)
    val input = DocumentInput("content://image", "image.png", "image/png", byteArrayOf(1, 2, 3))

    val result = KnowledgeIngestor(store = store, nowEpochMs = { 1_000 }).ingest(input)

    assertTrue(result is IngestResult.Failed)
    result as IngestResult.Failed
    assertEquals(IngestFailureCode.UNSUPPORTED_DOCUMENT_TYPE, result.code)
    assertEquals(listOf("dedupe:${Sha256.hex(input.bytes)}"), events)
    assertTrue(store.persistedChunks.isEmpty())
  }

  private class RecordingStore(
    private val events: MutableList<String>,
    private val existingDocumentId: String? = null,
  ) : KnowledgeStore {
    var persistedDocument: KnowledgeDocumentRecord? = null
    var persistedChunks: List<KnowledgeChunk> = emptyList()

    override suspend fun findDocumentIdBySha256(sha256: String): String? {
      events += "dedupe:$sha256"
      return existingDocumentId
    }

    override suspend fun insertDocumentWithChunks(
      document: KnowledgeDocumentRecord,
      chunks: List<KnowledgeChunk>,
    ) {
      events += "persist"
      persistedDocument = document
      persistedChunks = chunks
    }

    override suspend fun searchFts(matchQuery: String, limit: Int): List<KnowledgeSearchHit> = emptyList()
    override suspend fun searchLike(escapedNeedle: String, limit: Int): List<KnowledgeSearchHit> = emptyList()
  }
}
