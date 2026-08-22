package com.google.ai.edge.gallery.pocketgallery.knowledge.parser

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput

class TextDocumentParser : DocumentParser {
  override fun supports(input: DocumentInput): Boolean =
    input.mimeType.equals("text/plain", ignoreCase = true) ||
      input.displayName.lowercase().endsWith(".txt")

  override fun parse(input: DocumentInput): NormalizedDocument {
    val text = decodeNormalizedUtf8(input.bytes)
    val sections = if (text.isBlank()) emptyList() else listOf(NormalizedSection(null, text))
    return NormalizedDocument(text = text, sections = sections)
  }
}
