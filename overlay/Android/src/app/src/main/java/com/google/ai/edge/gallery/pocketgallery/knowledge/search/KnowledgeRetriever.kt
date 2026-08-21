package com.google.ai.edge.gallery.pocketgallery.knowledge.search

import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeSearchHit
import com.google.ai.edge.gallery.pocketgallery.knowledge.store.KnowledgeStore

class KnowledgeRetriever(
  private val store: KnowledgeStore,
) {
  suspend fun search(rawQuery: String, topK: Int = 8): List<KnowledgeSearchHit> {
    val limit = topK.coerceIn(1, 50)
    return when (val plan = KnowledgeQuery.plan(rawQuery)) {
      is KnowledgeQueryPlan.Fts -> store.searchFts(plan.matchQuery, limit)
      is KnowledgeQueryPlan.Like -> store.searchLike(plan.escapedNeedle, limit)
    }
  }
}
