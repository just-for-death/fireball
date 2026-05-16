package com.fireball.nativeapp.data

import com.fireball.nativeapp.core.data.FireballApiClient
import com.fireball.nativeapp.core.data.LibraryStore
import com.fireball.nativeapp.core.model.Artist
import com.fireball.nativeapp.core.model.FireballSettings
import com.fireball.nativeapp.core.model.LibrarySnapshot
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class FireballRepositoryReleaseTest {
  private val json = Json { ignoreUnknownKeys = true; isLenient = true }

  @Test
  fun checkFollowedArtistNewReleases_resolvesNameOnlyArtistIdAndStoresBaseline() = runTest {
    val lookupBody =
      """
      {"results":[{"artistId":4242,"artistName":"Resolved Artist"}]}
      """.trimIndent()
    val albumsBody =
      """
      {"results":[{"wrapperType":"collection","collectionId":"album-99","collectionName":"Fresh LP"}]}
      """.trimIndent()

    var requestCount = 0
    val engine =
      MockEngine { request ->
        requestCount++
        when {
          request.url.parameters["entity"] == "musicArtist" ->
            respond(
              lookupBody,
              HttpStatusCode.OK,
              headersOf("Content-Type", "application/json"),
            )
          request.url.parameters["entity"] == "album" ->
            respond(
              albumsBody,
              HttpStatusCode.OK,
              headersOf("Content-Type", "application/json"),
            )
          else -> respond("", HttpStatusCode.NotFound)
        }
      }
    val client =
      HttpClient(engine) {
        install(ContentNegotiation) { json(json) }
      }
    val storeDir = File.createTempFile("fireball-lib", "").apply { delete(); mkdirs() }
    val repo = FireballRepository(FireballApiClient(client), LibraryStore(storeDir))
    val snapshot =
      LibrarySnapshot(
        artists =
          listOf(
            Artist(artistId = "Resolved Artist", name = "Resolved Artist", artwork = null, latestReleaseId = null),
          ),
        settings = FireballSettings(notifyArtistReleasesOnDevice = true),
      )

    var notified = false
    val updated =
      repo.checkFollowedArtistNewReleases(
        snapshot = snapshot,
        onGotifyNotify = null,
        onDeviceNotify = { _, _ -> notified = true },
      )

    assertNotNull(updated)
    assertEquals("4242", updated!!.artists.single().artistId)
    assertEquals("album-99", updated.artists.single().latestReleaseId)
    assertTrue(requestCount >= 2)
    assertEquals(false, notified)
  }
}
