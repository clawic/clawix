package com.example.clawix.android.composer

import com.example.clawix.android.core.WireAttachment
import com.example.clawix.android.core.WireAttachmentKind
import com.example.clawix.android.util.Base64Util
import java.util.UUID

/**
 * Composer-side attachment with a preview reference plus the bytes
 * needed to ship via wire. Mirrors iOS `ComposerAttachment`.
 */
data class ComposerAttachment(
    val id: String = UUID.randomUUID().toString(),
    val kind: WireAttachmentKind,
    val mimeType: String,
    val filename: String?,
    val bytes: ByteArray,
) {
    fun toWire(): WireAttachment = WireAttachment(
        id = id,
        kind = kind,
        mimeType = mimeType,
        filename = filename,
        dataBase64 = Base64Util.encode(bytes),
    )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ComposerAttachment) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
