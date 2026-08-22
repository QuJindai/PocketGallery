package com.google.ai.edge.gallery.pocketgallery.knowledge.search

import org.junit.Assert.assertEquals
import org.junit.Test

class KnowledgeQueryTest {
  @Test
  fun whitespaceIsNormalizedAndLongQueryUsesQuotedFts() {
    assertEquals(
      KnowledgeQueryPlan.Fts("\"smart factory\""),
      KnowledgeQuery.plan("  smart   \n factory  "),
    )
  }

  @Test
  fun fewerThanThreeUnicodeCodePointsUsesLikeFallback() {
    assertEquals(KnowledgeQueryPlan.Like("智造"), KnowledgeQuery.plan("智造"))
    assertEquals(KnowledgeQueryPlan.Like("AI"), KnowledgeQuery.plan(" AI "))
  }

  @Test
  fun threeUnicodeCodePointsUsesFts() {
    assertEquals(KnowledgeQueryPlan.Fts("\"智能制\""), KnowledgeQuery.plan("智能制"))
  }

  @Test
  fun ftsQuotesAreEscaped() {
    assertEquals(
      KnowledgeQueryPlan.Fts("\"alpha \"\"beta\"\"\""),
      KnowledgeQuery.plan("alpha \"beta\""),
    )
  }

  @Test
  fun likeWildcardsAndEscapeCharacterAreEscaped() {
    assertEquals(KnowledgeQueryPlan.Like("a\\%"), KnowledgeQuery.plan("a%"))
    assertEquals(KnowledgeQueryPlan.Like("a\\_"), KnowledgeQuery.plan("a_"))
    assertEquals(KnowledgeQueryPlan.Like("a\\\\"), KnowledgeQuery.plan("a\\"))
  }

  @Test(expected = IllegalArgumentException::class)
  fun blankQueryIsRejected() {
    KnowledgeQuery.plan(" \n\t ")
  }
}
