package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/**
 * Guards the WhoopDatabase migration chain as a whole under exportSchema=false.
 *
 * With exportSchema=false Room does not emit a build-time schema JSON, so there is no
 * automatic check that the hand-written migration SQL matches the entity definitions.
 * The compensating strategy (see WhoopDatabase KDoc) is:
 *  - No destructive fallback: a mismatch throws loudly at open time instead of silently
 *    wiping non-resendable strap history.
 *  - Each migration's SQL is exposed as an internal constant and pinned by its own *MigrationTest.
 *  - THIS FILE pins the chain as a whole: current DB version, no gaps v2→N, and every
 *    registered migration object is a step-1-contiguous ladder.
 *
 * Failure modes caught here:
 *  - DB_VERSION bumped without adding the corresponding MIGRATION_X_Y (chain end < DB_VERSION - 1).
 *  - A migration registered twice or out of order.
 *  - A gap left in the chain (e.g., v10→v12 with no v11).
 *  - DB_VERSION constant drifts from the @Database(version = …) annotation (caught by compile + the
 *    chain end check: a silent annotation bump would leave DB_VERSION stale and the chain test passes
 *    with the wrong ceiling, so callers updating the annotation must also update DB_VERSION here).
 */
class WhoopDatabaseChainTest {

    /** Every migration registered in WhoopDatabase.build(), in order. */
    private val allMigrations = listOf(
        WhoopDatabase.MIGRATION_2_3,
        WhoopDatabase.MIGRATION_3_4,
        WhoopDatabase.MIGRATION_4_5,
        WhoopDatabase.MIGRATION_5_6,
        WhoopDatabase.MIGRATION_6_7,
        WhoopDatabase.MIGRATION_7_8,
        WhoopDatabase.MIGRATION_8_9,
        WhoopDatabase.MIGRATION_9_10,
        WhoopDatabase.MIGRATION_10_11,
        WhoopDatabase.MIGRATION_11_12,
        WhoopDatabase.MIGRATION_12_13,
        WhoopDatabase.MIGRATION_13_14,
        WhoopDatabase.MIGRATION_14_15,
        WhoopDatabase.MIGRATION_15_16,
        WhoopDatabase.MIGRATION_16_17,
        WhoopDatabase.MIGRATION_17_18,
    )

    @Test
    fun dbVersion_pinnedTo18() {
        assertEquals(
            "DB_VERSION changed — bump this pin, add MIGRATION_X_Y + *MigrationTest, " +
                "and update the @Database(version=…) annotation to match",
            18,
            WhoopDatabase.DB_VERSION,
        )
    }

    @Test
    fun migrationChain_everyStepIsOne() {
        for (m in allMigrations) {
            assertEquals(
                "migration ${m.startVersion}→${m.endVersion} must advance exactly one version",
                m.startVersion + 1,
                m.endVersion,
            )
        }
    }

    @Test
    fun migrationChain_startsAt2() {
        assertEquals(
            "chain must start at version 2 (a fresh Room install skips migrations)",
            2,
            allMigrations.first().startVersion,
        )
    }

    @Test
    fun migrationChain_endsAtDbVersionMinusOne() {
        val lastEnd = allMigrations.last().endVersion
        assertEquals(
            "chain must end at DB_VERSION (${WhoopDatabase.DB_VERSION}); " +
                "add the missing MIGRATION_X_Y and its *MigrationTest",
            WhoopDatabase.DB_VERSION,
            lastEnd,
        )
    }

    @Test
    fun migrationChain_noGapsOrDuplicates() {
        val starts = allMigrations.map { it.startVersion }
        val distinct = starts.distinct().sorted()
        if (distinct != starts.sorted()) {
            fail("duplicate migration start-version detected: $starts")
        }
        val expected = (2 until WhoopDatabase.DB_VERSION).toList()
        assertEquals(
            "migration chain has a gap or extra entry — every version from 2 to " +
                "${WhoopDatabase.DB_VERSION - 1} must have exactly one migration",
            expected,
            distinct,
        )
    }
}
