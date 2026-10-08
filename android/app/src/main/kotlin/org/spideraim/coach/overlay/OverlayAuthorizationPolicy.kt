package org.spideraim.coach.overlay

/**
 * Independent native authorization boundary for the overlay. Flutter supplies
 * presentation state, never capture evidence. Only the capture service calls
 * [nativeFrame] and the service lifecycle calls [nativeStarted]/[nativeStopped].
 *
 * Confidence is always a finite fraction in 0..1, not a percentage. The native
 * gate repeats the temporal proof requirement so a forged/manual Flutter state
 * cannot make a single screen frame safe. No method grants a manual override.
 * Android injects SystemClock.elapsedRealtime for [elapsedClockMs]; tests may
 * inject the same deterministic clock for both clocks.
 */
class OverlayAuthorizationPolicy(
    private val clockMs: () -> Long = { System.currentTimeMillis() },
    private val elapsedClockMs: () -> Long = clockMs,
) {
    companion object {
        private const val HEARTBEAT_TTL_MS = 3_000L
        private const val FRAME_TTL_MS = 5_000L
        private const val PROOF_WINDOW_MS = 12_000L
        private const val MINIMUM_SPAN_MS = 6_000L
        private const val MINIMUM_FRAMES = 4
        private const val FUTURE_TOLERANCE_MS = 2_000L
        private const val SAFE_CONFIDENCE = .95
        private const val AMBIGUOUS_CONFIDENCE = .50
        private const val COMPETITIVE_CONFIDENCE = .80
        private val SAFE_MODES = setOf(
            "TRAINING_SAFE", "WAREHOUSE_SAFE", "ARENA_SAFE", "SAFE_UNRANKED",
        )
        private val PUBG_PACKAGES = setOf(
            "com.tencent.ig", "com.pubg.krmobile", "com.pubg.imobile",
            "com.vng.pubgmobile", "com.rekoo.pubgm",
        )
        private val COMPETITIVE_CUES = setOf(
            "airplane", "flight_path", "jump", "follow", "free_fall",
            "parachute", "br_map", "ranked_label",
        )
        private val EXPECTED_REGIONS = mapOf(
            "training_label" to "mode_label",
            "warehouse_label" to "mode_label",
            "arena_label" to "mode_label",
            "tdm_label" to "mode_label",
            "unranked_label" to "mode_label",
            "target_practice" to "center",
            "training_controls" to "bottom_controls",
            "score_hud" to "top_hud",
            "round_timer" to "top_hud",
            "respawn_transition" to "top_hud",
        )
    }

    @Volatile var competitiveLatched: Boolean = false
        private set
    @Volatile var lastReason: String = "CAPTURE_NOT_STARTED"
        private set

    private data class Time(val wall: Long, val elapsed: Long)
    private data class Cue(val id: String, val confidence: Double, val region: String)
    private data class NativeProof(
        val mode: String,
        val timestampMs: Long,
        val received: Time,
        val foregroundPackage: String,
    )
    private data class DartState(
        val mode: String?,
        val allowed: Boolean,
        val confidence: Double?,
        val captureRunning: Boolean,
        val busy: Boolean?,
        val sessionId: String?,
        val received: Time,
    )

    private var activeSessionId: String? = null
    private var nativeRunning = false
    private var dartState: DartState? = null
    private var latestFrame: NativeProof? = null
    private val proofs = mutableListOf<NativeProof>()
    private val recentFingerprints = ArrayDeque<String>()
    private var lastSequence: Long? = null
    private var lastTimestampMs: Long? = null
    private var lastClock: Time? = null
    private var clockRollbackBlocked = false

    /** Reusing a consent/session ID, including after stop, never clears BR. */
    @Synchronized fun nativeStarted(sessionId: String) {
        val now = readTime()
        invalidateProof()
        dartState = null
        if (sessionId.isBlank()) {
            nativeRunning = false
            lastReason = "INVALID_CAPTURE_SESSION"
            return
        }
        if (activeSessionId != sessionId) {
            activeSessionId = sessionId
            competitiveLatched = false
            clockRollbackBlocked = false
            lastClock = now
            lastSequence = null
            lastTimestampMs = null
            recentFingerprints.clear()
        }
        nativeRunning = true
        lastReason = if (competitiveLatched) "COMPETITIVE_BLOCKED" else "WAITING_FOR_NATIVE_PROOF"
    }

    /** Stopping revokes every safe proof but preserves the session's BR latch. */
    @Synchronized fun nativeStopped() {
        readTime()
        nativeRunning = false
        dartState = null
        invalidateProof()
        lastReason = if (competitiveLatched) "COMPETITIVE_BLOCKED" else "CAPTURE_STOPPED"
    }

    /** Only accepted from the actual native capture pipeline, never a channel argument. */
    @Synchronized fun nativeFrame(
        sessionId: String,
        captureAuthorized: Boolean,
        foregroundVerified: Boolean,
        foregroundPackage: String?,
        timestampMs: Long,
        sequence: Long,
        fingerprint: String?,
        cues: List<Map<String, Any?>>,
    ) {
        val now = readTime()
        if (!nativeRunning || sessionId != activeSessionId) {
            lastReason = "NATIVE_SESSION_MISMATCH"
            return
        }
        if (competitiveLatched) {
            lastReason = "COMPETITIVE_BLOCKED"
            return
        }
        if (clockRollbackBlocked) {
            blockProof("CLOCK_ROLLBACK")
            return
        }
        if (!captureAuthorized || !foregroundVerified || foregroundPackage !in PUBG_PACKAGES) {
            blockProof("NATIVE_CAPTURE_NOT_VERIFIED")
            return
        }
        if (!freshSourceTimestamp(timestampMs, now.wall)) {
            blockProof("NATIVE_FRAME_TIMESTAMP_INVALID")
            return
        }
        val parsed = parseCues(cues)
        if (parsed == null) {
            blockProof("NATIVE_CUES_INVALID")
            return
        }
        // A real BR hazard immediately revokes the native surface, including a
        // repeated fingerprint. Duplicate detection must never mask a hazard.
        if (parsed.any { it.id in COMPETITIVE_CUES && it.confidence >= COMPETITIVE_CONFIDENCE }) {
            competitiveLatched = true
            blockProof("COMPETITIVE_BLOCKED")
            return
        }
        if (parsed.any { it.id in COMPETITIVE_CUES && it.confidence >= AMBIGUOUS_CONFIDENCE }) {
            blockProof("AMBIGUOUS_COMPETITIVE_CUE")
            return
        }
        if (sequence < 0 || fingerprint.isNullOrBlank() || fingerprint in recentFingerprints ||
            lastSequence?.let { sequence <= it } == true ||
            lastTimestampMs?.let { timestampMs <= it } == true
        ) {
            blockProof("DUPLICATE_OR_OUT_OF_ORDER_FRAME")
            return
        }
        lastSequence = sequence
        lastTimestampMs = timestampMs
        recentFingerprints.addLast(fingerprint)
        if (recentFingerprints.size > 32) recentFingerprints.removeFirst()

        val nativeMode = classify(parsed)
        if (nativeMode == null) {
            blockProof("INSUFFICIENT_OR_CONFLICTING_NATIVE_CUES")
            return
        }
        val previousProof = proofs.lastOrNull()
        if (previousProof != null && (previousProof.mode != nativeMode ||
                previousProof.foregroundPackage != foregroundPackage)) invalidateProof()
        proofs.removeAll { !freshReceipt(it.received, now, PROOF_WINDOW_MS) }
        val proof = NativeProof(nativeMode, timestampMs, now, requireNotNull(foregroundPackage))
        proofs.add(proof)
        if (proofs.size > 32) proofs.removeAt(0)
        latestFrame = proof
        lastReason = "WAITING_FOR_NATIVE_TEMPORAL_PROOF"
    }

    /** `mode` is an enum code; event timestamps supplied by Flutter are ignored. */
    @Synchronized fun updateState(state: Map<String, Any?>) {
        val now = readTime()
        dartState = DartState(
            mode = state["mode"] as? String,
            allowed = state["allowed"] == true,
            confidence = fraction(state["confidence"]),
            captureRunning = state["captureRunning"] == true,
            busy = state["busy"] as? Boolean,
            sessionId = state["sessionId"] as? String,
            received = now,
        )
    }

    /** All caller arguments must come from native service/UsageStats state. */
    @Synchronized fun authorize(
        captureRunning: Boolean,
        currentSessionId: String?,
        foregroundPackage: String?,
        foregroundVerified: Boolean,
    ): Boolean {
        val now = readTime()
        fun denied(reason: String): Boolean { lastReason = reason; return false }
        if (competitiveLatched) return denied("COMPETITIVE_BLOCKED")
        if (clockRollbackBlocked) return denied("CLOCK_ROLLBACK")
        if (!nativeRunning || !captureRunning) return denied("CAPTURE_STOPPED")
        if (currentSessionId == null || currentSessionId != activeSessionId) {
            return denied("NATIVE_SESSION_MISMATCH")
        }
        if (!foregroundVerified || foregroundPackage !in PUBG_PACKAGES) {
            return denied("PUBG_NOT_FOREGROUND")
        }
        val state = dartState ?: return denied("NO_DART_STATE")
        if (!freshReceipt(state.received, now, HEARTBEAT_TTL_MS)) return denied("DART_HEARTBEAT_STALE")
        if (state.sessionId != activeSessionId || !state.captureRunning) {
            return denied("DART_CAPTURE_SESSION_MISMATCH")
        }
        if (state.mode !in SAFE_MODES || !state.allowed) return denied("MODE_BLOCKED")
        if (state.confidence == null || state.confidence < SAFE_CONFIDENCE) {
            return denied("SAFE_CONFIDENCE_INSUFFICIENT")
        }
        val frame = latestFrame ?: return denied("NO_NATIVE_FRAME_PROOF")
        if (!freshReceipt(frame.received, now, FRAME_TTL_MS) ||
            !freshSourceTimestamp(frame.timestampMs, now.wall)
        ) return denied("NATIVE_FRAME_STALE")
        if (frame.foregroundPackage != foregroundPackage) return denied("FOREGROUND_PACKAGE_CHANGED")
        if (frame.mode != state.mode) return denied("NATIVE_DART_MODE_MISMATCH")
        proofs.removeAll { !freshReceipt(it.received, now, PROOF_WINDOW_MS) }
        val first = proofs.firstOrNull() ?: return denied("NO_NATIVE_TEMPORAL_PROOF")
        if (proofs.size < MINIMUM_FRAMES ||
            frame.timestampMs - first.timestampMs < MINIMUM_SPAN_MS ||
            frame.received.elapsed - first.received.elapsed < MINIMUM_SPAN_MS
        ) return denied("INSUFFICIENT_NATIVE_TEMPORAL_PROOF")
        // Busy is a transient presentation state, not a safety explanation.
        // Never let it conceal lost native proof from the surface manager.
        if (state.busy != false) return denied("STATE_BUSY_OR_INVALID")
        lastReason = "AUTHORIZED"
        return true
    }

    private fun readTime(): Time {
        val now = Time(clockMs(), elapsedClockMs())
        val previous = lastClock
        if (previous != null && (now.wall < previous.wall || now.elapsed < previous.elapsed)) {
            clockRollbackBlocked = true
            invalidateProof()
            dartState = null
            lastReason = "CLOCK_ROLLBACK"
        }
        lastClock = now
        return now
    }

    private fun freshReceipt(received: Time, now: Time, ttlMs: Long): Boolean =
        now.wall >= received.wall && now.elapsed >= received.elapsed &&
            now.wall - received.wall <= ttlMs && now.elapsed - received.elapsed <= ttlMs

    private fun freshSourceTimestamp(timestamp: Long, wall: Long): Boolean =
        timestamp >= 0 && wall >= 0 &&
            if (timestamp > wall) timestamp - wall <= FUTURE_TOLERANCE_MS
            else wall - timestamp <= FRAME_TTL_MS

    private fun invalidateProof() {
        latestFrame = null
        proofs.clear()
    }

    private fun blockProof(reason: String) {
        invalidateProof()
        lastReason = reason
    }

    private fun fraction(value: Any?): Double? = (value as? Number)?.toDouble()?.takeIf {
        it.isFinite() && it in 0.0..1.0
    }

    private fun parseCues(raw: List<Map<String, Any?>>): List<Cue>? {
        val parsed = mutableListOf<Cue>()
        for (item in raw) {
            val id = item["id"] as? String ?: return null
            val confidence = fraction(item["confidence"]) ?: return null
            val region = item["region"] as? String ?: return null
            if (id.isBlank() || region.isBlank()) return null
            if (EXPECTED_REGIONS[id]?.let { it != region } == true) return null
            parsed.add(Cue(id, confidence, region))
        }
        return parsed
    }

    private fun classify(cues: List<Cue>): String? {
        // Keep the weakest duplicate confidence. Duplicating a cue can never
        // manufacture a second independent indicator or inflate confidence.
        val confidences = cues.groupBy { it.id }.mapValues { (_, group) -> group.minOf { it.confidence } }
        // A weaker duplicate cannot hide a conflicting observed mode label.
        fun plausible(id: String) = cues.any { it.id == id && it.confidence >= AMBIGUOUS_CONFIDENCE }
        fun strong(id: String) = (confidences[id] ?: 0.0) >= SAFE_CONFIDENCE
        val training = plausible("training_label")
        val warehouse = plausible("warehouse_label")
        val arena = !warehouse && (plausible("arena_label") || plausible("tdm_label"))
        if (listOf(training, warehouse, arena).count { it } > 1) return null
        if (training) return if (strong("training_label") &&
            (strong("target_practice") || strong("training_controls"))) "TRAINING_SAFE" else null
        if (warehouse || arena) {
            val strongLabel = if (warehouse) strong("warehouse_label")
                else strong("arena_label") || strong("tdm_label")
            // The transition cue is produced only with a real scoreboard and
            // timer. Require their explicit corroboration in the native gate.
            val hud = strong("score_hud") &&
                (strong("round_timer") || strong("respawn_transition"))
            return if (strongLabel && hud) {
                if (warehouse) "WAREHOUSE_SAFE" else "ARENA_SAFE"
            } else null
        }
        if (!strong("unranked_label")) return null
        val practice = strong("target_practice") && strong("training_controls")
        val match = strong("score_hud") && strong("round_timer") && strong("respawn_transition")
        return if (practice || match) "SAFE_UNRANKED" else null
    }
}
