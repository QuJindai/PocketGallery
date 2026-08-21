package com.google.ai.edge.gallery.pocketgallery.knowledge.parser

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput

class MarkdownDocumentParser : DocumentParser {
  private val heading = Regex("^(#{1,6})[ \\t]+(.+?)[ \\t]*#*[ \\t]*$")

  override fun supports(input: DocumentInput): Boolean {
    val name = input.displayName.lowercase()
    return input.mimeType.equals("text/markdown", ignoreCase = true) ||
      name.endsWith(".md") || name.endsWith(".markdown")
  }

  override fun parse(input: DocumentInput): NormalizedDocument {
    val text = decodeNormalizedUtf8(input.bytes)
    if (text.isBlank()) return NormalizedDocument(text, emptyList())

    val headings = mutableListOf<Pair<Int, String>>()
    var lineStart = 0
    while (lineStart <= text.length) {
      val newline = text.indexOf('\n', lineStart)
      val lineEnd = if (newline < 0) text.length else newline
      val line = text.substring(lineStart, lineEnd)
      heading.matchEntire(line)?.let { match ->
        headings += lineStart to match.groupValues[2].trim()
      }
      if (newline < 0) break
      lineStart = newline + 1
    }

    if (headings.isEmpty()) {
      return NormalizedDocument(text, listOf(NormalizedSection(null, text)))
    }

    val sections = mutableListOf<NormalizedSection>()
    if (headings.first().first > 0) {
      val prefix = text.substring(0, headings.first().first)
      if (prefix.isNotBlank()) sections += NormalizedSection(null, prefix)
    }
    headings.forEachIndexed { index, (start, label) ->
      val end = headings.getOrNull(index + 1)?.first ?: text.length
      val body = text.substring(start, end)
      if (body.isNotBlank()) sections += NormalizedSection(label, body)
    }
    return NormalizedDocument(text, sections)
  }
}
