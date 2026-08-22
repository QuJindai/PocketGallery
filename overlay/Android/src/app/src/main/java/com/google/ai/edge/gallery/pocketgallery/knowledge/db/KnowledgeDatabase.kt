package com.google.ai.edge.gallery.pocketgallery.knowledge.db

import android.content.Context
import androidx.room3.Database
import androidx.room3.Room
import androidx.room3.RoomDatabase
import androidx.sqlite.driver.bundled.BundledSQLiteDriver

@Database(
  entities = [
    KnowledgeDocumentEntity::class,
    KnowledgeChunkEntity::class,
    KnowledgeChunkFts::class,
  ],
  version = 1,
  exportSchema = false,
)
abstract class KnowledgeDatabase : RoomDatabase() {
  abstract fun knowledgeDao(): KnowledgeDao

  companion object {
    fun build(context: Context): KnowledgeDatabase =
      Room.databaseBuilder(
        context.applicationContext,
        KnowledgeDatabase::class.java,
        "pocketgallery-knowledge.db",
      )
        .setDriver(BundledSQLiteDriver())
        .build()
  }
}
