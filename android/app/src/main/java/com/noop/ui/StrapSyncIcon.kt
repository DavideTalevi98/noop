package com.noop.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.ble.LiveState
import kotlinx.coroutines.delay

/** Compact strap-history sync affordance — Android twin of [StrapSyncButton]. */
@Composable
fun StrapSyncIcon(
    live: LiveState,
    onSyncNow: () -> Unit,
    onOpenDevices: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
    liquidStyle: Boolean = false,
) {
    val action = StrapSyncAction.resolve(live.connected, live.bonded, live.backfilling)
    val spinning = action == StrapSyncAction.Syncing
    var wasBackfilling by remember { mutableStateOf(live.backfilling) }
    val completeOpacity = remember { Animatable(0f) }

    LaunchedEffect(live.backfilling, live.lastSyncError) {
        if (StrapSyncAction.shouldFlashComplete(wasBackfilling, live.backfilling, live.lastSyncError)) {
            completeOpacity.snapTo(1f)
            delay(900)
            completeOpacity.animateTo(0f, tween(500))
        }
        wasBackfilling = live.backfilling
    }

    val ringRotation = if (spinning) {
        rememberInfiniteTransition(label = "strapSyncSpin").animateFloat(
            initialValue = 0f,
            targetValue = 360f,
            animationSpec = infiniteRepeatable(tween(1100, easing = LinearEasing)),
            label = "strapSyncAngle",
        ).value
    } else {
        0f
    }

    val centerTint = when {
        completeOpacity.value > 0f -> Palette.statusPositive
        action == StrapSyncAction.Syncing -> Palette.metricCyan
        action == StrapSyncAction.Ready -> Palette.accent
        liquidStyle -> Color.White.copy(alpha = 0.85f)
        else -> Palette.textSecondary
    }
    val alpha = if (action == StrapSyncAction.Offline) 0.45f else 1f
    val enabled = action == StrapSyncAction.Ready || action == StrapSyncAction.Offline

    val a11y = when {
        completeOpacity.value > 0f -> "Strap history synced"
        action == StrapSyncAction.Offline -> "No strap connected. Opens Devices to connect your strap."
        action == StrapSyncAction.Pairing -> "Pairing strap. Sync becomes available when the strap is paired."
        action == StrapSyncAction.Ready -> "Sync strap history. Pulls your strap's stored history immediately."
        else -> "Syncing strap history. A sync is already in progress."
    }

    Box(
        modifier = modifier
            .size(size)
            .semantics { contentDescription = a11y }
            .then(
                if (enabled) {
                    Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        enabled = enabled,
                        onClick = {
                            when (action) {
                                StrapSyncAction.Offline -> onOpenDevices()
                                StrapSyncAction.Ready -> onSyncNow()
                                else -> Unit
                            }
                        },
                    )
                } else {
                    Modifier
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    if (liquidStyle) Color.White.copy(alpha = 0.16f) else Palette.surfaceInset,
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Sensors,
                contentDescription = null,
                tint = centerTint.copy(alpha = alpha),
                modifier = Modifier.size(size * 0.42f),
            )
            Canvas(Modifier.matchParentSize().padding(2.dp)) {
                val stroke = 2.5.dp.toPx()
                val arcDiameter = this.size.minDimension - stroke
                val inset = (this.size.minDimension - arcDiameter) / 2f
                val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)
                val arcSize = androidx.compose.ui.geometry.Size(arcDiameter, arcDiameter)
                if (completeOpacity.value > 0f) {
                    drawCircle(
                        color = Palette.statusPositive.copy(alpha = completeOpacity.value),
                        radius = arcDiameter / 2f,
                        center = center,
                        style = Stroke(width = stroke),
                    )
                } else if (spinning) {
                    drawArc(
                        color = Palette.metricCyan,
                        startAngle = ringRotation,
                        sweepAngle = 100f,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                    )
                }
            }
        }
    }
}

/** Convenience overload that reads [AppViewModel.live] and wires sync/devices. */
@Composable
fun StrapSyncIcon(
    vm: AppViewModel,
    onOpenDevices: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 34.dp,
    liquidStyle: Boolean = false,
) {
    val live by vm.live.collectAsStateWithLifecycle()
    StrapSyncIcon(
        live = live,
        onSyncNow = { vm.syncNow() },
        onOpenDevices = onOpenDevices,
        modifier = modifier,
        size = size,
        liquidStyle = liquidStyle,
    )
}
