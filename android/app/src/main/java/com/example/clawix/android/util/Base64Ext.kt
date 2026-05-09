package com.example.clawix.android.util

import android.util.Base64

object Base64Util {
    fun encode(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_WRAP)

    fun decode(raw: String): ByteArray =
        Base64.decode(raw, Base64.DEFAULT)
}
