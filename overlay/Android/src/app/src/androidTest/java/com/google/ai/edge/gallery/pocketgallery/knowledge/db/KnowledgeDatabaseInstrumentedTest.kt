package com.google.ai.edge.gallery.pocketgallery.knowledge.db

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeDatabaseInstrumentedTest {
  private lateinit var database: KnowledgeDatabase
  private lateinit var dao: KnowledgeDao

  @Before
  fun setUp() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    database = Room.inMemoryDatabaseBuilder(context, KnowledgeDatabase::class.java)
      .setDriver(BundledSQLiteDriver())
      .build()
    dao = database.knowledgeDao()
  }

  @After
  fun tearDown() {
    database.close()
  }

  @Test
  fun bundledSqliteFts5IndexesEnglishAndChineseAndTracksDeletes() = runBlocking {
    val document = KnowledgeDocumentEntity(
      documentId = "doc-1",
      sourceUri = "content://fixture/manufacturing.md",
      displayName = "manufacturing.md",
      mimeType = "text/markdown",
      sha256 = "abc123",
      sizeBytes = 128,
      importedAtEpochMs = 1_000,
      modifiedAtEpochMs = 900,
      parseStatus = "ready",
      parseError = null,
    )
    dao.insertDocument(document)
    dao.insertChunks(
      listOf(
        KnowledgeChunkEntity(
          chunkId = "chunk-en",
          documentId = document.documentId,
          ordinal = 0,
          pageOrSection = "Manufacturing",
          text = "smart manufacturing evidence stays local",
          charStart = 0,
          charEnd = 40,
          tokenEstimate = 10,
        ),
        KnowledgeChunkEntity(
          chunkId = "chunk-zh",
          documentId = document.documentId,
          ordinal = 1,
          pageOrSection = "智能制造",
          text = "智能制造知识证据保存在本地设备",
          charStart = 41,
          charEnd = 57,
          tokenEstimate = 4,
        ),
      ),
    )

    assertEquals(document.documentId, dao.findDocumentIdBySha256("abc123"))
    assertEquals(listOf("chunk-en"), dao.searchFts("manufacturing", 8).map { it.chunkId })
    assertEquals(listOf("chunk-zh"), dao.searchFts("智能制造", 8).map { it.chunkId })

    dao.deleteDocument(document.documentId)
    assertTrue(dao.searchFts("manufacturing", 8).isEmpty())
    assertTrue(dao.searchFts("智能制造", 8).isEmpty())
  }
}
