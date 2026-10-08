package org.spideraim.coach.overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OverlayAuthorizationPolicyTest {
    companion object {
        private const val PUBG = "com.tencent.ig"

        private fun cue(id: String, confidence: Double = .97): Map<String, Any?> {
            val region = when (id) {
                "training_label", "warehouse_label", "arena_label", "tdm_label", "unranked_label" -> "mode_label"
                "training_controls" -> "bottom_controls"
                "target_practice", "free_fall", "parachute", "jump", "follow" -> "center"
                else -> "top_hud"
            }
            return mapOf("id" to id, "confidence" to confidence, "region" to region)
        }

        private fun warehouse() = listOf(cue("warehouse_label"), cue("score_hud"), cue("round_timer"))
        private fun training() = listOf(cue("training_label"), cue("target_practice"))
        private fun arena() = listOf(cue("tdm_label"), cue("score_hud"), cue("round_timer"))
        private fun unranked() = listOf(cue("unranked_label"), cue("target_practice"), cue("training_controls"))
    }

    private class Fixture {
        var wall = 100_000L
        var elapsed = 10_000L
        var sequence = 0L
        var session = "native-session-A"
        val policy = OverlayAuthorizationPolicy(clockMs = { wall }, elapsedClockMs = { elapsed })

        init { policy.nativeStarted(session) }

        fun advance(ms: Long) { wall += ms; elapsed += ms }

        fun frame(
            cues: List<Map<String, Any?>> = warehouse(),
            timestamp: Long = wall,
            frameSequence: Long = ++sequence,
            fingerprint: String? = "frame-$frameSequence",
            authorized: Boolean = true,
            foregroundVerified: Boolean = true,
            foregroundPackage: String? = PUBG,
            frameSession: String = session,
        ) = policy.nativeFrame(frameSession, authorized, foregroundVerified,
            foregroundPackage, timestamp, frameSequence, fingerprint, cues)

        fun state(mode: String = "WAREHOUSE_SAFE", overrides: Map<String, Any?> = emptyMap()) =
            policy.updateState(mapOf(
                "mode" to mode, "allowed" to true, "confidence" to .97,
                "captureRunning" to true, "busy" to false, "sessionId" to session,
            ) + overrides)

        fun authorize(
            running: Boolean = true,
            currentSession: String? = session,
            foregroundPackage: String? = PUBG,
            foregroundVerified: Boolean = true,
        ) = policy.authorize(running, currentSession, foregroundPackage, foregroundVerified)

        fun safe(mode: String = "WAREHOUSE_SAFE", cues: List<Map<String, Any?>> = warehouse()) {
            repeat(4) { index -> frame(cues); if (index < 3) advance(2_000) }
            state(mode)
        }
    }

    @Test fun fourIndependentFramesAndMatchingFreshStateAuthorize() {
        val f = Fixture()
        f.safe()
        assertTrue(f.authorize())
        assertEquals("AUTHORIZED", f.policy.lastReason)
    }

    @Test fun allSupportedSafeModesRequireTheirOwnNativeProof() {
        for ((mode, cues) in listOf(
            "TRAINING_SAFE" to training(), "WAREHOUSE_SAFE" to warehouse(),
            "ARENA_SAFE" to arena(), "SAFE_UNRANKED" to unranked(),
        )) {
            val f = Fixture()
            f.safe(mode, cues)
            assertTrue(mode, f.authorize())
        }
    }

    @Test fun aSingleActualFrameCannotBeOverriddenBySafeDartState() {
        val f = Fixture()
        f.frame()
        f.state()
        assertFalse(f.authorize())
        assertEquals("INSUFFICIENT_NATIVE_TEMPORAL_PROOF", f.policy.lastReason)
    }

    @Test fun fourRapidFramesStillCannotClaimSixSecondsOfEvidence() {
        val f = Fixture()
        repeat(4) { f.frame(); f.advance(100) }
        f.state()
        assertFalse(f.authorize())
    }

    @Test fun flutterCannotSupplyNativeFramesOrSpoofHeartbeatTimestamps() {
        val f = Fixture()
        f.state(overrides = mapOf(
            "timestampMs" to Long.MAX_VALUE, "cues" to warehouse(),
            "frameCount" to 999, "nativeVerified" to true,
        ))
        assertFalse(f.authorize())
        assertEquals("NO_NATIVE_FRAME_PROOF", f.policy.lastReason)
        f.safe()
        f.advance(3_001)
        assertFalse(f.authorize())
        assertEquals("DART_HEARTBEAT_STALE", f.policy.lastReason)
    }

    @Test fun staleNativeFramesBlockEvenWithFreshDartHeartbeat() {
        val f = Fixture()
        f.safe()
        f.advance(5_001)
        f.state()
        assertFalse(f.authorize())
        assertEquals("NATIVE_FRAME_STALE", f.policy.lastReason)
    }

    @Test fun unknownAndCompetitiveModesCannotBeMadeSafeWithAllowedFlag() {
        for (mode in listOf("UNKNOWN_BLOCKED", "COMPETITIVE_BLOCKED", "TRAINING", "SAFE")) {
            val f = Fixture()
            f.safe()
            f.state(mode)
            assertFalse(mode, f.authorize())
            assertEquals("MODE_BLOCKED", f.policy.lastReason)
        }
    }

    @Test fun zeroConfidencePercentagesAndInvalidFractionsFailClosed() {
        for (confidence in listOf(0.0, .949, 97, Double.NaN, Double.POSITIVE_INFINITY, -1, "0.99", null)) {
            val f = Fixture()
            f.safe()
            f.state(overrides = mapOf("confidence" to confidence))
            assertFalse("confidence=$confidence", f.authorize())
            assertEquals("SAFE_CONFIDENCE_INSUFFICIENT", f.policy.lastReason)
        }
    }

    @Test fun requiredDartFieldsCannotBeOmittedOrCoercedFromStrings() {
        for ((key, value) in listOf(
            "allowed" to "true", "captureRunning" to "true", "busy" to "false",
            "sessionId" to null, "mode" to null, "busy" to null,
        )) {
            val f = Fixture()
            f.safe()
            f.state(overrides = mapOf(key to value))
            assertFalse(key, f.authorize())
        }
    }

    @Test fun explicitRejectionAndBusyStateBlockNativeActions() {
        val f = Fixture()
        f.safe()
        f.state(overrides = mapOf("allowed" to false))
        assertFalse(f.authorize())
        f.state(overrides = mapOf("busy" to true))
        assertFalse(f.authorize())
        assertEquals("STATE_BUSY_OR_INVALID", f.policy.lastReason)
    }

    @Test fun busyStateCannotConcealAmbiguousBattleRoyaleProofRevocation() {
        val f = Fixture()
        f.safe()
        f.advance(1)
        f.frame(warehouse() + cue("airplane", .65))
        f.state(overrides = mapOf("busy" to true))
        assertFalse(f.authorize())
        assertEquals("NO_NATIVE_FRAME_PROOF", f.policy.lastReason)
    }

    @Test fun busyStateCannotConcealStaleNativeProof() {
        val f = Fixture()
        f.safe()
        f.advance(5_001)
        f.state(overrides = mapOf("busy" to true))
        assertFalse(f.authorize())
        assertEquals("NATIVE_FRAME_STALE", f.policy.lastReason)
    }

    @Test fun actualCaptureAndBothSessionChecksCannotBeOverridden() {
        val f = Fixture()
        f.safe()
        assertFalse(f.authorize(running = false))
        assertFalse(f.authorize(currentSession = null))
        assertFalse(f.authorize(currentSession = "different-native-session"))
        f.state(overrides = mapOf("sessionId" to "different-dart-session"))
        assertFalse(f.authorize())
    }

    @Test fun captureStopClearsAllSafeProofAndHeartbeat() {
        val f = Fixture()
        f.safe()
        f.policy.nativeStopped()
        f.state()
        assertFalse(f.authorize())
        f.policy.nativeStarted(f.session)
        f.state()
        assertFalse(f.authorize())
        assertEquals("NO_NATIVE_FRAME_PROOF", f.policy.lastReason)
    }

    @Test fun liveForegroundChecksAndPackageChangesBlock() {
        val f = Fixture()
        f.safe()
        assertFalse(f.authorize(foregroundVerified = false))
        assertFalse(f.authorize(foregroundPackage = "com.example.other"))
        assertFalse(f.authorize(foregroundPackage = null))
        assertFalse(f.authorize(foregroundPackage = "com.pubg.krmobile"))
        assertEquals("FOREGROUND_PACKAGE_CHANGED", f.policy.lastReason)
    }

    @Test fun allFiveKnownPubgPackagesMayProvideNativeEvidence() {
        for (pkg in listOf("com.tencent.ig", "com.pubg.krmobile", "com.pubg.imobile",
            "com.vng.pubgmobile", "com.rekoo.pubgm")) {
            val f = Fixture()
            repeat(4) { index -> f.frame(foregroundPackage = pkg); if (index < 3) f.advance(2_000) }
            f.state()
            assertTrue(pkg, f.authorize(foregroundPackage = pkg))
        }
    }

    @Test fun switchingBetweenPubgInstallationsRequiresNewTemporalProof() {
        val f = Fixture()
        f.safe()
        f.advance(2_000)
        f.frame(foregroundPackage = "com.pubg.krmobile")
        f.state()
        assertFalse(f.authorize(foregroundPackage = "com.pubg.krmobile"))
        assertEquals("INSUFFICIENT_NATIVE_TEMPORAL_PROOF", f.policy.lastReason)
    }

    @Test fun anyCaptureOrForegroundFailureRevokesPreviouslySafeEvidence() {
        for (failure in listOf("capture", "foreground", "package")) {
            val f = Fixture()
            f.safe()
            f.advance(1)
            f.frame(authorized = failure != "capture", foregroundVerified = failure != "foreground",
                foregroundPackage = if (failure == "package") "com.example.other" else PUBG)
            f.state()
            assertFalse(failure, f.authorize())
        }
    }

    @Test fun everyStrongBattleRoyaleCueImmediatelyLatchesDespiteSafeDartState() {
        for (hazard in listOf("airplane", "flight_path", "jump", "follow", "free_fall",
            "parachute", "br_map", "ranked_label")) {
            val f = Fixture()
            f.safe()
            assertTrue(f.authorize())
            f.advance(1)
            f.frame(warehouse() + cue(hazard, .80))
            f.state()
            assertTrue(hazard, f.policy.competitiveLatched)
            assertFalse(hazard, f.authorize())
            assertEquals("COMPETITIVE_BLOCKED", f.policy.lastReason)
        }
    }

    @Test fun battleRoyaleCueOnRepeatedFrameStillImmediatelyLatches() {
        val f = Fixture()
        f.safe()
        f.frame(warehouse() + cue("airplane", .99), frameSequence = f.sequence,
            fingerprint = "frame-${f.sequence}")
        assertTrue(f.policy.competitiveLatched)
        assertFalse(f.authorize())
    }

    @Test fun weakBattleRoyaleCueRevokesProofWithoutClaimingCertainCause() {
        for (confidence in listOf(.50, .65, .7999)) {
            val f = Fixture()
            f.safe()
            f.advance(1)
            f.frame(warehouse() + cue("parachute", confidence))
            assertFalse(f.policy.competitiveLatched)
            f.state()
            assertFalse(f.authorize())
        }
    }

    @Test fun sameSessionRestartAndStopCannotClearCompetitiveLatch() {
        val f = Fixture()
        f.frame(listOf(cue("airplane", .90)))
        f.policy.nativeStarted(f.session)
        f.safe()
        assertTrue(f.policy.competitiveLatched)
        assertFalse(f.authorize())
        f.policy.nativeStopped()
        f.policy.nativeStarted(f.session)
        f.state()
        assertTrue(f.policy.competitiveLatched)
        assertFalse(f.authorize())
    }

    @Test fun onlyNewNativeSessionClearsLatchAndStillNeedsFreshEvidence() {
        val f = Fixture()
        f.frame(listOf(cue("airplane", .90)))
        f.session = "native-session-B"
        f.policy.nativeStarted(f.session)
        f.state()
        assertFalse(f.policy.competitiveLatched)
        assertFalse(f.authorize())
        f.safe()
        assertTrue(f.authorize())
    }

    @Test fun dartSessionOrModeUpdateCannotClearCompetitiveLatch() {
        val f = Fixture()
        f.frame(listOf(cue("ranked_label", .99)))
        f.state(overrides = mapOf("sessionId" to "fabricated-session", "competitiveLatched" to false))
        assertTrue(f.policy.competitiveLatched)
        assertFalse(f.authorize(currentSession = "fabricated-session"))
    }

    @Test fun duplicateFingerprintsSequencesAndOutOfOrderTimestampsRevokeProof() {
        for (failure in listOf("fingerprint", "sequence", "timestamp", "missing", "negative")) {
            val f = Fixture()
            f.safe()
            val oldSequence = f.sequence
            f.advance(1)
            f.frame(frameSequence = if (failure == "sequence") oldSequence else if (failure == "negative") -1 else ++f.sequence,
                fingerprint = when (failure) { "fingerprint" -> "frame-$oldSequence"; "missing" -> null; else -> "new-frame" },
                timestamp = if (failure == "timestamp") f.wall - 1 else f.wall)
            f.state()
            assertFalse(failure, f.authorize())
        }
    }

    @Test fun repeatedNonAdjacentFingerprintCannotInflateFrameCount() {
        val f = Fixture()
        f.frame(fingerprint = "replayed-image")
        f.advance(2_000)
        f.frame()
        f.advance(2_000)
        f.frame()
        f.advance(2_000)
        f.frame(fingerprint = "replayed-image")
        f.state()
        assertFalse(f.authorize())
    }

    @Test fun modeLabelAloneAndUnsupportedHudCannotMakeSafeProof() {
        for (cues in listOf(
            listOf(cue("warehouse_label")),
            listOf(cue("warehouse_label"), cue("round_timer")),
            listOf(cue("training_label"), cue("score_hud"), cue("round_timer")),
            listOf(cue("unranked_label"), cue("score_hud"), cue("round_timer")),
        )) {
            val f = Fixture()
            f.safe(cues = cues)
            assertFalse(f.authorize())
        }
    }

    @Test fun explicitHudRegionsAndMinimumCueConfidenceAreRequired() {
        for (badCue in listOf(
            cue("score_hud", .949),
            cue("score_hud") + mapOf("region" to "mode_label"),
            cue("score_hud") + mapOf("confidence" to 97),
            cue("score_hud") + mapOf("confidence" to Double.NaN),
            cue("score_hud") + mapOf("region" to null),
        )) {
            val f = Fixture()
            f.safe(cues = listOf(cue("warehouse_label"), badCue, cue("round_timer")))
            assertFalse(f.authorize())
        }
    }

    @Test fun duplicateWeakCueCannotBeHiddenBehindAStrongerDuplicate() {
        val f = Fixture()
        f.safe(cues = warehouse() + cue("warehouse_label", .60))
        assertFalse(f.authorize())
    }

    @Test fun uncertainConflictingModeLabelsRevokePreviouslySafeProof() {
        val f = Fixture()
        f.safe()
        f.advance(1)
        f.frame(warehouse() + cue("training_label", .50))
        f.state()
        assertFalse(f.authorize())
        assertFalse(f.policy.competitiveLatched)
    }

    @Test fun weakDuplicateCannotHideAPlausibleConflictingMode() {
        val f = Fixture()
        f.safe(cues = warehouse() + cue("training_label", .70) + cue("training_label", .10))
        assertFalse(f.authorize())
    }

    @Test fun warehouseMayAlsoDisplayGenericArenaAndTdmLabels() {
        val f = Fixture()
        f.safe(cues = warehouse() + cue("arena_label") + cue("tdm_label"))
        assertTrue(f.authorize())
    }

    @Test fun actualNativeModeMustMatchDartModeAndTransitionsResetTemporalProof() {
        val f = Fixture()
        f.safe()
        f.state("TRAINING_SAFE")
        assertFalse(f.authorize())
        assertEquals("NATIVE_DART_MODE_MISMATCH", f.policy.lastReason)
        f.advance(1)
        f.frame(training())
        f.state("TRAINING_SAFE")
        assertFalse(f.authorize())
        assertEquals("INSUFFICIENT_NATIVE_TEMPORAL_PROOF", f.policy.lastReason)
    }

    @Test fun staleAndFarFutureSourceTimestampsRevokeProof() {
        for (offset in listOf(-5_001L, 2_001L)) {
            val f = Fixture()
            f.safe()
            f.advance(1)
            f.frame(timestamp = f.wall + offset)
            f.state()
            assertFalse(f.authorize())
        }
    }

    @Test fun oldSessionFramesCannotProvideProofOrLatchNewSession() {
        val f = Fixture()
        f.session = "native-session-B"
        f.policy.nativeStarted(f.session)
        f.frame(listOf(cue("airplane")), frameSession = "native-session-A")
        assertFalse(f.policy.competitiveLatched)
        f.state()
        assertFalse(f.authorize())
    }

    @Test fun wallClockRollbackBlocksUntilFreshNativeSession() {
        val f = Fixture()
        f.safe()
        f.wall -= 1
        assertFalse(f.authorize())
        assertEquals("CLOCK_ROLLBACK", f.policy.lastReason)
        f.state()
        f.safe()
        assertFalse(f.authorize())
        f.session = "native-session-B"
        f.policy.nativeStarted(f.session)
        f.safe()
        assertTrue(f.authorize())
    }

    @Test fun monotonicClockRollbackAlsoBlocksUntilFreshNativeSession() {
        val f = Fixture()
        f.safe()
        f.elapsed -= 1
        assertFalse(f.authorize())
        assertEquals("CLOCK_ROLLBACK", f.policy.lastReason)
    }

    @Test fun monotonicAgeCannotBeMaskedByFrozenWallClock() {
        val f = Fixture()
        f.safe()
        f.elapsed += 5_001
        f.state()
        assertFalse(f.authorize())
        assertEquals("NATIVE_FRAME_STALE", f.policy.lastReason)
    }

    @Test fun invalidNativeSessionCannotAuthorizeAndDoesNotClearExistingLatch() {
        val f = Fixture()
        f.frame(listOf(cue("airplane")))
        f.policy.nativeStarted("")
        f.state()
        assertTrue(f.policy.competitiveLatched)
        assertFalse(f.authorize())
    }
}
