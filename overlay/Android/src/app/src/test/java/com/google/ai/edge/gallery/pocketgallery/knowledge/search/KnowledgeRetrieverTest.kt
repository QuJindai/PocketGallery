package com.google.ai.edge.gallery.pocketgallery.knowledge.search

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.KnowledgeChunk
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeDocumentRecord
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeSearchHit
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class KnowledgeRetrieverTest {
  @Test
  fun ftsQueryUsesClampedTopK() = runBlocking {
    val store = RecordingStore()
    KnowledgeRetriever(store).search("智能制造", topK = 99)
    assertEquals("\"智能制造\"" to 50, store.lastFts)
    assertEquals(null, store.lastLike)
  }

  @Test
  fun shortQueryUsesLikeFallbackAndDefaultTopK() = runBlocking {
    val store = RecordingStore()
    KnowledgeRetriever(store).search("AI")
    assertEquals("AI" to 8, store.lastLike)
    assertEquals(null, store.lastFts)
  }

  private class RecordingStore : KnowledgeStore {
    var lastFts: Pair<String, Int>? = null
    var lastLike: Pair<String, Int>? = null

    override suspend fun findDocumentIdBySha256(sha256: String): String? = null
    override suspend fun insertDocumentWithChunks(
      document: KnowledgeDocumentRecord,
      chunks: List<KnowledgeChunk>,
    ) = Unit

    override suspend fun searchFts(matchQuery: String, limit: Int): List<KnowledgeSearchHit> {
      lastFts = matchQuery to limit
      return emptyList()
    }

    override suspend fun searchLike(escapedNeedle: String, limit: Int): List<KnowledgeSearchHit> {
      lastLike = escapedNeedle to limit
      return emptyList()
    }
  }
}
