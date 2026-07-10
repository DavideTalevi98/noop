package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the v17 -> v18 Room migration that widens `rrInterval`'s PK to add a `seq` tiebreaker (#163,
 * approach from @tanarchytan), and the pure `assignRrSeq` insert helper that populates it. No Robolectric
 * here, so — like the other migration tests — the SQL is exposed as [WhoopDatabase.RR_SEQ_MIGRATION_SQL]
 * and pinned to Room's generated v18 shape: the rebuilt table's column order + PK MUST match [RrInterval]
 * exactly (deviceId, ts, rrMs, seq, synced; PK deviceId, ts, rrMs, seq) or the no-destructive-fallback
 * open throws. The seq logic is exercised directly.
 */
class RrSeqMigrationTest {

    @Test
    fun migration_versionPair_is17to18() {
        assertEquals(17, WhoopDatabase.MIGRATION_17_18.startVersion)
        assertEquals(18, WhoopDatabase.MIGRATION_17_18.endVersion)
    }

    @Test
    fun migration_rebuildsTable_matchingRoomGeneratedSchema() {
        assertEquals(
            listOf(
                "CREATE TABLE IF NOT EXISTS `rrInterval_new` (`deviceId` TEXT NOT NULL, `ts` INTEGER NOT NULL, " +
                    "`rrMs` INTEGER NOT NULL, `seq` INTEGER NOT NULL, `synced` INTEGER NOT NULL, " +
                    "PRIMARY KEY(`deviceId`, `ts`, `rrMs`, `seq`))",
                "INSERT INTO `rrInterval_new` (`deviceId`, `ts`, `rrMs`, `seq`, `synced`) " +
                    "SELECT `deviceId`, `ts`, `rrMs`, 0, `synced` FROM `rrInterval`",
                "DROP TABLE `rrInterval`",
                "ALTER TABLE `rrInterval_new` RENAME TO `rrInterval`",
            ),
            WhoopDatabase.RR_SEQ_MIGRATION_SQL,
        )
    }

    @Test
    fun migration_isLossless_copiesEveryRowWithSeqZero() {
        val sql = WhoopDatabase.RR_SEQ_MIGRATION_SQL
        val insert = sql.single { it.startsWith("INSERT") }.uppercase()
        // Copies EVERY row from the old table — no WHERE / GROUP BY — with seq forced to 0. Exact because
        // the old PK (deviceId, ts, rrMs) was unique per row, so seq 0 never collides.
        assertTrue("copies from the old table", insert.contains("FROM `RRINTERVAL`"))
        assertTrue("no row filter or dedupe", !insert.contains(" WHERE ") && !insert.contains(" GROUP BY "))
        // seq must sit before synced in both the CREATE and the entity, so Room's column order matches.
        val create = sql.single { it.startsWith("CREATE") }
        assertTrue("seq column declared before synced", create.indexOf("`seq`") < create.indexOf("`synced`"))
    }

    @Test
    fun assignRrSeq_keepsEqualSameSecondBeats_withDistinctSeq() {
        // Two EQUAL intervals in the same second: both survive, seq 0 then 1 — the pair the old key dropped.
        val out = assignRrSeq("my-whoop", listOf(RrRow(100, 812), RrRow(100, 812)))
        assertEquals(2, out.size)
        assertEquals(listOf(0, 1), out.map { it.seq })
        assertTrue(out.all { it.ts == 100L && it.rrMs == 812 && it.deviceId == "my-whoop" })
    }

    @Test
    fun assignRrSeq_distinctBeats_keepSeqZero() {
        // Distinct (ts, rrMs) beats each keep seq 0 — including two different values in the same second.
        val out = assignRrSeq("d", listOf(RrRow(100, 602), RrRow(100, 613), RrRow(101, 602)))
        assertEquals(listOf(0, 0, 0), out.map { it.seq })
    }

    @Test
    fun assignRrSeq_distinctCrossBatchBeats_doNotCollide() {
        // Distinct beats arriving in SEPARATE batches keep their own (ts, rrMs, 0) key — different rrMs =
        // different PK, so IGNORE-on-conflict keeps both (the regression a ts-only counter would cause).
        val b1 = assignRrSeq("d", listOf(RrRow(100, 602)))
        val b2 = assignRrSeq("d", listOf(RrRow(100, 613)))
        assertEquals(0, b1.single().seq)
        assertEquals(0, b2.single().seq)
    }

    @Test
    fun assignRrSeq_isIdempotent_reSyncReproducesSameKeys() {
        val rows = listOf(RrRow(100, 812), RrRow(100, 812), RrRow(101, 700))
        assertEquals(assignRrSeq("d", rows), assignRrSeq("d", rows))
    }

    @Test
    fun rrInterval_seq_defaultsToZero() {
        assertEquals(0, RrInterval(deviceId = "d", ts = 1, rrMs = 800).seq)
    }
}
