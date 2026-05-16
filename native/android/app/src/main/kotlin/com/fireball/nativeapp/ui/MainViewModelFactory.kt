package com.fireball.nativeapp.ui

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.fireball.nativeapp.data.FireballRepository
import com.fireball.nativeapp.data.IntegrationOrchestrator
import com.fireball.nativeapp.data.LyricsAndAiOrchestrator
import com.fireball.nativeapp.player.PlaybackController
import com.fireball.nativeapp.player.PlayerManager

class MainViewModelFactory(
    private val appContext: Context,
    private val repository: FireballRepository,
    private val playerManager: PlayerManager,
    private val integrations: IntegrationOrchestrator,
    private val playbackController: PlaybackController,
    private val lyricsAndAi: LyricsAndAiOrchestrator,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(MainViewModel::class.java)) {
            return MainViewModel(
                appContext.applicationContext,
                repository,
                playerManager,
                integrations,
                playbackController,
                lyricsAndAi,
            ) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
    }
}
