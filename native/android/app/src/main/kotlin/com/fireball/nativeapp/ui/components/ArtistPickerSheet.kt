package com.fireball.nativeapp.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.ui.MainViewModel
import com.fireball.nativeapp.ui.theme.MotionTokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class ArtistPickerContext(
    val names: List<String>,
    val fallbackArtwork: String? = null,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArtistPickerSheet(
    context: ArtistPickerContext,
    viewModel: MainViewModel,
    onDismiss: () -> Unit,
    onSelect: (String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var thumbnails by remember(context.names) { mutableStateOf<Map<String, String?>>(emptyMap()) }
    var loading by remember(context.names) { mutableStateOf(true) }

    LaunchedEffect(context.names, context.fallbackArtwork) {
        loading = true
        val map = mutableMapOf<String, String?>()
        for (name in context.names) {
            val url =
                try {
                    withContext(Dispatchers.IO) {
                        viewModel.resolveArtistThumbnail(name, context.fallbackArtwork)
                    }
                } catch (_: Exception) {
                    context.fallbackArtwork
                }
            map[name] = url
        }
        thumbnails = map
        loading = false
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDragHandle() },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
        ) {
            Text(
                text = "Choose artist",
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = "This track lists multiple artists.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            Spacer(Modifier.height(12.dp))
            if (loading && thumbnails.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.padding(24.dp))
            } else {
                context.names.forEachIndexed { index, name ->
                    SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * index.coerceAtMost(6)) {
                        ActionSheetRowWithAvatar(
                            imageUrl = thumbnails[name] ?: context.fallbackArtwork,
                            label = name,
                            onClick = {
                                onSelect(name)
                                onDismiss()
                            },
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * 2) {
                ActionSheetRow(
                    icon = Icons.Default.Close,
                    label = "Cancel",
                    onClick = onDismiss,
                )
            }
        }
    }
}
