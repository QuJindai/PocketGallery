package com.google.ai.edge.gallery.pocketgallery.knowledge.parser

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput

class ParserRegistry(
  private val parsers: List<DocumentParser> = listOf(MarkdownDocumentParser(), TextDocumentParser()),
) {
  fun parserFor(input: DocumentInput): DocumentParser =
    parsers.firstOrNull { it.supports(input) } ?: throw UnsupportedDocumentTypeException(input)

  fun parse(input: DocumentInput): NormalizedDocument = parserFor(input).parse(input)
}
