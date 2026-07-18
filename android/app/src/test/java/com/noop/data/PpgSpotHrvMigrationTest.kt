package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the additive v18 -> v19 Room migration (`ppgSpotHrvSample`), twin of Swift WhoopStore v25.
 * Plain-JVM pin of the CREATE TABLE SQL to Room's generated [PpgSpotHrvSample] shape.
 */
class PpgSpotHrvMigrationTest {

    @Test
    fun migration_isAdditive_onlyCreateTable() {
        val sql = WhoopDatabase.PPG_SPOT_HRV_MIGRATION_SQL
        assertEquals(1, sql.size)
        val up = sql[0].trimStart().uppercase()
        assertTrue(up.startsWith("CREATE TABLE"))
        for (banned in listOf("DROP ", "DELETE ", "UPDATE ", "INSERT ", "ALTER ")) {
            assertTrue(!up.contains(banned))
        }
    }

    @Test
    fun migration_createsExactTable() {
        assertEquals(
            listOf(
                "CREATE TABLE IF NOT EXISTS `ppgSpotHrvSample` (`deviceId` TEXT NOT NULL, " +
                    "`ts` INTEGER NOT NULL, `rmssdMs` REAL NOT NULL, `hrBpm` REAL NOT NULL, " +
                    "`beats` INTEGER NOT NULL, `quality` TEXT NOT NULL, " +
                    "PRIMARY KEY(`deviceId`, `ts`))",
            ),
            WhoopDatabase.PPG_SPOT_HRV_MIGRATION_SQL,
        )
    }

    @Test
    fun migration_versionPair_is18to19() {
        assertEquals(18, WhoopDatabase.MIGRATION_18_19.startVersion)
        assertEquals(19, WhoopDatabase.MIGRATION_18_19.endVersion)
    }
}
