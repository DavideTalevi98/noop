package com.noop.ui

/** Pure tap routing for the Polar-style strap sync chrome — JVM-testable without BLE. */
enum class StrapSyncAction {
    Offline, Pairing, Ready, Syncing;

    companion object {
        fun resolve(connected: Boolean, bonded: Boolean, backfilling: Boolean): StrapSyncAction = when {
            backfilling -> Syncing
            !connected -> Offline
            !bonded -> Pairing
            else -> Ready
        }

        fun shouldFlashComplete(wasBackfilling: Boolean, backfilling: Boolean, lastSyncError: String?): Boolean =
            wasBackfilling && !backfilling && lastSyncError == null
    }
}
