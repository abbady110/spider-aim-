package org.spideraim.coach.capture

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** In-process lifecycle bridge. No frame, OCR text, or token is persisted/replayed. */
object CaptureEvents {
    private val main = Handler(Looper.getMainLooper())
    var sink: EventChannel.EventSink? = null
    var startListener: ((Map<String, Any?>) -> Unit)? = null
    @Volatile var running = false
        private set
    @Volatile var sessionId: String? = null
        private set
    @Volatile var lastReason: String? = null
        private set

    fun prepare(id: String) {
        check(Looper.myLooper() == Looper.getMainLooper())
        sessionId = id
        running = false
        lastReason = null
    }

    fun status(): Map<String, Any?> = mapOf(
        "supported" to true,
        "started" to running,
        "sessionId" to sessionId,
        "reason" to lastReason
    )

    fun started(id: String) {
        main.post {
            sessionId = id
            running = true
            lastReason = null
            val event = mapOf("type" to "started", "sessionId" to id,
                "timestampMs" to System.currentTimeMillis())
            sink?.success(event)
            startListener?.invoke(status())
            startListener = null
        }
    }

    fun emit(event: Map<String, Any?>) {
        main.post {
            // Discard OCR completions from a service/session that has already stopped.
            if (running && event["sessionId"] == sessionId) sink?.success(event)
        }
    }

    fun stopped(id: String?, reason: String) {
        main.post {
            if (id != null && sessionId != null && sessionId != id) return@post
            sessionId = id ?: sessionId
            running = false
            lastReason = reason
            sink?.success(mapOf("type" to "stopped", "sessionId" to sessionId,
                "reason" to reason, "timestampMs" to System.currentTimeMillis()))
            startListener?.invoke(status())
            startListener = null
        }
    }
}
