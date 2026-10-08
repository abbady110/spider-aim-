package org.spideraim.coach.capture

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.CopyOnWriteArrayList

/** In-process lifecycle bridge. No frame, OCR text, or token is persisted/replayed. */
object CaptureEvents {
    private val main = Handler(Looper.getMainLooper())
    var sink: EventChannel.EventSink? = null
    var startListener: ((Map<String, Any?>) -> Unit)? = null
    private val observers = linkedSetOf<(Map<String, Any?>) -> Unit>()
    private val proofObservers = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()

    /** No View work here: proof is revoked on the capture worker before queued UI taps. */
    fun addImmediateProofObserver(observer: (Map<String, Any?>) -> Unit) { proofObservers.add(observer) }
    fun removeImmediateProofObserver(observer: (Map<String, Any?>) -> Unit) { proofObservers.remove(observer) }
    private fun observeProof(event: Map<String, Any?>) { proofObservers.forEach { it(event) } }

    fun addObserver(observer: (Map<String, Any?>) -> Unit) {
        check(Looper.myLooper() == Looper.getMainLooper())
        observers.add(observer)
    }

    fun removeObserver(observer: (Map<String, Any?>) -> Unit) {
        check(Looper.myLooper() == Looper.getMainLooper())
        observers.remove(observer)
    }

    private fun observe(event: Map<String, Any?>) {
        // Only native service events reach these observers. Dart updateState
        // cannot forge fresh frames or clear their competitive latch.
        observers.toList().forEach { it(event) }
    }
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
        val event = mapOf("type" to "prepared", "sessionId" to id)
        observeProof(event)
        observe(event)
    }

    fun status(): Map<String, Any?> = mapOf(
        "supported" to true,
        "started" to running,
        "sessionId" to sessionId,
        "reason" to lastReason
    )

    fun started(id: String) {
        // The service has already created its consented projection/display.
        sessionId = id
        running = true
        lastReason = null
        val event = mapOf("type" to "started", "sessionId" to id,
            "timestampMs" to System.currentTimeMillis())
        observeProof(event)
        main.post {
            if (!running || sessionId != id) return@post
            observe(event)
            sink?.success(event)
            startListener?.invoke(status())
            startListener = null
        }
    }

    fun emit(event: Map<String, Any?>) {
        if (!running || event["sessionId"] != sessionId) return
        observeProof(event)
        main.post {
            // Discard OCR completions from a service/session that has already stopped.
            if (running && event["sessionId"] == sessionId) {
                observe(event)
                sink?.success(event)
            }
        }
    }

    fun stopped(id: String?, reason: String) {
        if (id != null && sessionId != null && sessionId != id) return
        running = false
        lastReason = reason
        val event = mapOf("type" to "stopped", "sessionId" to (id ?: sessionId),
            "reason" to reason, "timestampMs" to System.currentTimeMillis())
        observeProof(event)
        main.post {
            if (id != null && sessionId != null && sessionId != id) return@post
            sessionId = id ?: sessionId
            observe(event)
            sink?.success(event)
            startListener?.invoke(status())
            startListener = null
        }
    }
}
