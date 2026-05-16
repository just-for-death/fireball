package com.fireball.nativeapp.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fireball.nativeapp.ui.theme.MotionTokens

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArtistPickerSheet(
    artists: List<String>,
    onDismiss: () -> Unit,
    onSelect: (String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
            artists.forEachIndexed { index, name ->
                SuvFadeSlideIn(delayMs = MotionTokens.DurationShort3 * index.coerceAtMost(6)) {
                    ActionSheetRow(
                        icon = Icons.Default.Person,
                        label = name,
                        onClick = {
                            onSelect(name)
                            onDismiss()
                        },
                    )
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
