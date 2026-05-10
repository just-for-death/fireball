package com.fireball.nativeapp.core.data

import com.fireball.nativeapp.core.model.LibrarySnapshot
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

class LibraryStore(
    private val storageDir: File,
    private val json: Json = Json { ignoreUnknownKeys = true; prettyPrint = true }
) {
    private val libraryFile: File
        get() = File(storageDir, "fireball_library.json")

    fun load(): LibrarySnapshot {
        if (!libraryFile.exists()) return LibrarySnapshot()
        return runCatching {
            json.decodeFromString(LibrarySnapshot.serializer(), libraryFile.readText())
        }.getOrElse { LibrarySnapshot() }
    }

    fun save(snapshot: LibrarySnapshot) {
        val tmp = File(storageDir, "fireball_library.json.tmp")
        tmp.writeText(json.encodeToString(LibrarySnapshot.serializer(), snapshot))
        tmp.renameTo(libraryFile)
    }
}
