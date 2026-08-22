package com.google.ai.edge.gallery.pocketgallery.knowledge.hash

import java.security.MessageDigest

object Sha256 {
  fun hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256")
      .digest(bytes)
      .joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }
}
