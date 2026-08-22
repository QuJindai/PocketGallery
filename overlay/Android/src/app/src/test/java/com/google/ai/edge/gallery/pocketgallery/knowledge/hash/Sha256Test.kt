package com.google.ai.edge.gallery.pocketgallery.knowledge.hash

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class Sha256Test {
  @Test
  fun fixedDigestIsLowercaseHex() {
    assertEquals(
      "873929fd92aabd6cb630b113c435d5dfa9803af55413a75513023fc22e5130e3",
      Sha256.hex("PocketGallery".toByteArray()),
    )
  }

  @Test
  fun digestIsDeterministicAndContentSensitive() {
    val first = Sha256.hex(byteArrayOf(1, 2, 3))
    assertEquals(first, Sha256.hex(byteArrayOf(1, 2, 3)))
    assertNotEquals(first, Sha256.hex(byteArrayOf(1, 2, 4)))
  }
}
