package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** Tap-routing matrix for the Polar-style strap sync chrome. Mirrors StrapSyncActionTests.swift. */
class StrapSyncActionTest {

    @Test
    fun backfillingWinsRegardlessOfLink() {
        assertEquals(StrapSyncAction.Syncing, StrapSyncAction.resolve(true, true, true))
        assertEquals(StrapSyncAction.Syncing, StrapSyncAction.resolve(false, false, true))
    }

    @Test
    fun offlineWhenDisconnected() {
        assertEquals(StrapSyncAction.Offline, StrapSyncAction.resolve(false, false, false))
        assertEquals(StrapSyncAction.Offline, StrapSyncAction.resolve(false, true, false))
    }

    @Test
    fun pairingWhenConnectedButNotBonded() {
        assertEquals(StrapSyncAction.Pairing, StrapSyncAction.resolve(true, false, false))
    }

    @Test
    fun readyWhenConnectedBondedIdle() {
        assertEquals(StrapSyncAction.Ready, StrapSyncAction.resolve(true, true, false))
    }
}
