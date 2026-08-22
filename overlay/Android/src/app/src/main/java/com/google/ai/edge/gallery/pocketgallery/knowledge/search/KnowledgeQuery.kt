package com.google.ai.edge.gallery.pocketgallery.knowledge.search

sealed interface KnowledgeQueryPlan {
  data class Fts(val matchQuery: String) : KnowledgeQueryPlan
  data class Like(val escapedNeedle: String) : KnowledgeQueryPlan
}

object KnowledgeQuery {
  fun plan(raw: String): KnowledgeQueryPlan {
    val normalized = raw.trim().replace(Regex("\\s+"), " ")
    require(normalized.isNotEmpty()) { "query must not be blank" }

    val codePointCount = normalized.codePointCount(0, normalized.length)
    return if (codePointCount < 3) {
      KnowledgeQueryPlan.Like(escapeLike(normalized))
    } else {
      KnowledgeQueryPlan.Fts("\"${normalized.replace("\"", "\"\"")}\"")
    }
  }

  private fun escapeLike(value: String): String = buildString(value.length) {
    value.forEach { char ->
      when (char) {
        '\\', '%', '_' -> append('\\')
      }
      append(char)
    }
  }
}
