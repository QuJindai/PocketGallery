package com.google.ai.edge.gallery.pocketgallery.knowledge.chunk

import com.google.ai.edge.gallery.pocketgallery.knowledge.hash.Sha256
import com.google.ai.edge.gallery.pocketgallery.knowledge.model.KnowledgeChunk
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.NormalizedDocument
import com.google.ai.edge.gallery.pocketgallery.knowledge.parser.NormalizedSection
import kotlin.math.max
import kotlin.math.min

class DocumentChunker(
  private val maxChars: Int = 1200,
  private val overlapChars: Int = 150,
) {
  init {
    require(maxChars > 0) { "maxChars must be positive" }
    require(overlapChars >= 0 && overlapChars < maxChars) {
      "overlapChars must be in 0 until maxChars"
    }
  }

  fun chunk(documentSha256: String, document: NormalizedDocument): List<KnowledgeChunk> {
    if (document.text.isBlank()) return emptyList()
    val sections = document.sections.ifEmpty { listOf(NormalizedSection(null, document.text)) }
    val chunks = mutableListOf<KnowledgeChunk>()
    var searchFrom = 0
    var ordinal = 0

    sections.forEach { section ->
      if (section.text.isBlank()) return@forEach
      val sectionStart = document.text.indexOf(section.text, startIndex = searchFrom)
        .takeIf { it >= 0 } ?: document.text.indexOf(section.text).takeIf { it >= 0 } ?: return@forEach
      searchFrom = sectionStart + section.text.length

      var localStart = 0
      while (localStart < section.text.length) {
        val hardEnd = min(localStart + maxChars, section.text.length)
        val localEnd = if (hardEnd == section.text.length) hardEnd
        else chooseBoundary(section.text, localStart, hardEnd)
        if (localEnd <= localStart) break

        val globalStart = sectionStart + localStart
        val globalEnd = sectionStart + localEnd
        val chunkText = document.text.substring(globalStart, globalEnd)
        chunks += KnowledgeChunk(
          chunkId = Sha256.hex("$documentSha256:$ordinal:$chunkText".toByteArray(Charsets.UTF_8)),
          ordinal = ordinal,
          pageOrSection = section.label,
          text = chunkText,
          charStart = globalStart,
          charEnd = globalEnd,
          tokenEstimate = (chunkText.length + 3) / 4,
        )
        ordinal += 1
        if (localEnd >= section.text.length) break
        localStart = max(localStart + 1, localEnd - overlapChars)
      }
    }
    return chunks
  }

  private fun chooseBoundary(text: String, start: Int, hardEnd: Int): Int {
    val minimum = start + (hardEnd - start) / 2
    fun lastDelimiter(delimiter: String): Int {
      val index = text.lastIndexOf(delimiter, startIndex = hardEnd - 1)
      return if (index >= minimum) index + delimiter.length else -1
    }
    return listOf(lastDelimiter("\n\n"), lastDelimiter("\n"), lastDelimiter(" "))
      .firstOrNull { it > start } ?: hardEnd
  }
}
