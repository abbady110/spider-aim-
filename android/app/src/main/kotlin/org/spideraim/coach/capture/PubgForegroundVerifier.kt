package org.spideraim.coach.capture

import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock

data class ForegroundEvidence(val packageName: String?, val verified: Boolean, val reason: String?)

/** Public usage lifecycle observations, never Accessibility or process inspection. */
class PubgForegroundVerifier(private val context: Context) {
    companion object {
        val pubgPackages = setOf("com.tencent.ig", "com.pubg.krmobile", "com.pubg.imobile",
            "com.vng.pubgmobile", "com.rekoo.pubgm")

        @Suppress("DEPRECATION")
        fun hasUsageAccess(context: Context): Boolean {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), context.packageName)
            } else {
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), context.packageName)
            }
            return mode == AppOpsManager.MODE_ALLOWED
        }
    }

    private var queryAfterMs = 0L
    private var currentPackage: String? = null
    private var lastLifecycleTimestampMs = 0L
    private var lastReadElapsedMs = 0L

    @Suppress("DEPRECATION")
    fun read(): ForegroundEvidence {
        if (!hasUsageAccess(context)) {
            currentPackage = null
            queryAfterMs = 0L
            return ForegroundEvidence(null, false, "USAGE_ACCESS_REQUIRED")
        }
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!power.isInteractive || keyguard.isKeyguardLocked) {
            currentPackage = null
            return ForegroundEvidence(null, false, "SCREEN_LOCKED_OR_OFF")
        }
        val now = System.currentTimeMillis()
        val elapsed = SystemClock.elapsedRealtime()
        // A lifecycle stream observed continuously remains valid until PAUSE/STOP or
        // another RESUME. On initial attach, do not trust an old unmatched resume.
        val firstRead = queryAfterMs == 0L
        val start = if (firstRead) now - 8_000L else queryAfterMs - 1L
        try {
            val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val events = manager.queryEvents(start, now)
                ?: return ForegroundEvidence(null, false, "USAGE_EVENTS_UNAVAILABLE")
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.timeStamp < lastLifecycleTimestampMs) continue
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                        currentPackage = event.packageName
                        lastLifecycleTimestampMs = event.timeStamp
                    }
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                        if (event.packageName == currentPackage) currentPackage = null
                        lastLifecycleTimestampMs = event.timeStamp
                    }
                    // ACTIVITY_STOPPED and SCREEN_NON_INTERACTIVE constants arrived in Q.
                    23 -> if (Build.VERSION.SDK_INT >= 29 && event.packageName == currentPackage) {
                        currentPackage = null
                        lastLifecycleTimestampMs = event.timeStamp
                    }
                    16 -> if (Build.VERSION.SDK_INT >= 28) {
                        currentPackage = null
                        lastLifecycleTimestampMs = event.timeStamp
                    }
                }
            }
            if (lastReadElapsedMs != 0L && elapsed - lastReadElapsedMs > 8_000L) {
                // Worker/OCR stalls invalidate the retained lifecycle state. A fresh
                // recent RESUME is needed again, rather than reusing stale foreground.
                currentPackage = null
                queryAfterMs = 0L
                lastReadElapsedMs = 0L
                return ForegroundEvidence(null, false, "FOREGROUND_OBSERVATION_STALE")
            }
            queryAfterMs = now
            lastReadElapsedMs = elapsed
            val current = currentPackage
            return ForegroundEvidence(current, current in pubgPackages,
                if (current in pubgPackages) null else "PUBG_NOT_VERIFIED_FOREGROUND")
        } catch (_: Exception) {
            currentPackage = null
            queryAfterMs = 0L
            lastReadElapsedMs = 0L
            return ForegroundEvidence(null, false, "FOREGROUND_VERIFICATION_UNAVAILABLE")
        }
    }
}
