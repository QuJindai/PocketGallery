package com.google.ai.edge.gallery.pocketgallery.knowledge.parser

import com.google.ai.edge.gallery.pocketgallery.knowledge.model.DocumentInput
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentParserTest {
  @Test
  fun txtRemovesBomAndNormalizesLineEndings() {
    val input = DocumentInput(
      sourceUri = "content://fixture/sample.txt",
      displayName = "sample.txt",
      mimeType = "text/plain",
      bytes = "\uFEFFalpha\r\nbeta\rgamma".toByteArray(Charsets.UTF_8),
    )
    val parsed = TextDocumentParser().parse(input)
    assertEquals("alpha\nbeta\ngamma", parsed.text)
    assertEquals(listOf(NormalizedSection(null, "alpha\nbeta\ngamma")), parsed.sections)
  }

  @Test
  fun markdownCreatesHeadingDerivedSections() {
    val input = DocumentInput(
      sourceUri = "content://fixture/sample.md",
      displayName = "sample.md",
      mimeType = "text/markdown",
      bytes = "intro\r\n# First\r\nalpha\r\n## Second\r\nbeta".toByteArray(),
    )
    val parsed = MarkdownDocumentParser().parse(input)
    assertEquals("intro\n# First\nalpha\n## Second\nbeta", parsed.text)
    assertEquals(listOf(null, "First", "Second"), parsed.sections.map { it.label })
    assertTrue(parsed.sections[1].text.startsWith("# First"))
    assertTrue(parsed.sections[2].text.startsWith("## Second"))
  }

  @Test
  fun registryAcceptsKnownExtensionsWhenMimeIsGeneric() {
    val registry = ParserRegistry()
    val markdown = DocumentInput("file://a", "note.MD", "application/octet-stream", "# x".toByteArray())
    val text = DocumentInput("file://b", "note.TXT", "application/octet-stream", "x".toByteArray())
    assertTrue(registry.parserFor(markdown) is MarkdownDocumentParser)
    assertTrue(registry.parserFor(text) is TextDocumentParser)
  }

  @Test(expected = UnsupportedDocumentTypeException::class)
  fun registryRejectsUnsupportedDocuments() {
    ParserRegistry().parse(
      DocumentInput("file://c", "image.png", "image/png", byteArrayOf(1, 2, 3)),
    )
  }
}
