package com.google.ai.edge.gallery.pocketgallery.knowledge.chunk

import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.NormalizedDocument
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.NormalizedSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentChunkerTest {
  @Test
  fun blankDocumentProducesNoChunks() {
    assertTrue(DocumentChunker().chunk("abc", NormalizedDocument("   ", emptyList())).isEmpty())
  }

  @Test
  fun shortDocumentProducesOneDeterministicChunk() {
    val document = NormalizedDocument("alpha beta", listOf(NormalizedSection(null, "alpha beta")))
    val first = DocumentChunker().chunk("docsha", document)
    val second = DocumentChunker().chunk("docsha", document)
    assertEquals(1, first.size)
    assertEquals(first, second)
    assertEquals(0, first.single().charStart)
    assertEquals(document.text.length, first.single().charEnd)
  }

  @Test
  fun longDocumentChunksWithBoundedOverlapAndOffsets() {
    val text = (1..120).joinToString(" ") { "paragraph$it" }
    val chunks = DocumentChunker(maxChars = 180, overlapChars = 30)
      .chunk("docsha", NormalizedDocument(text, listOf(NormalizedSection(null, text))))
    assertTrue(chunks.size > 1)
    chunks.forEach { chunk ->
      assertTrue(chunk.charStart < chunk.charEnd)
      assertEquals(text.substring(chunk.charStart, chunk.charEnd), chunk.text)
      assertTrue(chunk.text.length <= 180)
    }
    chunks.zipWithNext().forEach { (left, right) ->
      val overlap = left.charEnd - right.charStart
      assertTrue(overlap in 0..30)
    }
  }

  @Test
  fun markdownSectionLabelIsCarriedToChunks() {
    val text = "# Manufacturing\nsmart factory evidence"
    val chunks = DocumentChunker(maxChars = 100, overlapChars = 10).chunk(
      "docsha",
      NormalizedDocument(text, listOf(NormalizedSection("Manufacturing", text))),
    )
    assertEquals("Manufacturing", chunks.single().pageOrSection)
  }
}
