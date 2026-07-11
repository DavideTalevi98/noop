package com.noop.data

import android.content.Context
import android.content.Intent
import android.widget.Toast
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * After a `.noopbak` restore the on-disk DB is swapped but long-lived Room/BLE handles still point at
 * the closed connection (#57). Relaunch the process so the next open uses the restored file — same
 * guarantee as [com.noop.ui.BackupSyncScreen].
 */
object BackupRestart {
    suspend fun afterRestoreToastAndExit(context: Context, message: String = "Backup restored — restarting NOOP…") {
        Toast.makeText(context, message, Toast.LENGTH_LONG).show()
        withContext(NonCancellable) {
            delay(800)
            val ctx = context.applicationContext
            ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                ?.let { ctx.startActivity(it) }
            Runtime.getRuntime().exit(0)
        }
    }
}
