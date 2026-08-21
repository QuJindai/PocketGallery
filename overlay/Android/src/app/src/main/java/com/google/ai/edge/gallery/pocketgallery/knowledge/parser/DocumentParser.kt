package com.google.ai.edge.gallery.pocketgallery.knowledge.parser

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput

data class NormalizedSection(
  val label: String?,
  val text: String,
)

data class NormalizedDocument(
  val text: String,
  val sections: List<NormalizedSection>,
)

interface DocumentParser {
  fun supports(input: DocumentInput): Boolean
  fun parse(input: DocumentInput): NormalizedDocument
}

class UnsupportedDocumentTypeException(input: DocumentInput) :
  IllegalArgumentException("Unsupported document type: ${input.mimeType} (${input.displayName})")

internal fun decodeNormalizedUtf8(bytes: ByteArray): String {
  val raw = bytes.toString(Charsets.UTF_8).removePrefix("\uFEFF")
  return raw.replace("\r\n", "\n").replace("\r", "\n")
}
