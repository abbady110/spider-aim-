package org.spideraim.coach.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PubgCueExtractorTest {
    private fun word(
        text: String,
        confidence: Float = .97f,
        left: Float = .4f,
        top: Float = .1f,
        right: Float = left + .08f,
        bottom: Float = top + .035f,
    ) = OcrWord(text, confidence, left, top, right, bottom)

    private fun ids(words: List<OcrWord>, previousRespawn: Boolean = false) =
        PubgCueExtractor.extract(words, previousRespawn).map { it.id }.toSet()

    private fun scoreboard() = listOf(
        word("17", left = .34f),
        word("23", left = .58f),
        word("08:42", left = .46f, top = .18f),
    )

    @Test fun warehouseAloneNeverCreatesSafeHudEvidence() {
        assertEquals(setOf("warehouse_label"), ids(listOf(word("Warehouse"))))
    }

    @Test fun modeNamesMustBeWholeTokens() {
        assertTrue(ids(listOf(word("Warehouseman"), word("Trainingbot"))).isEmpty())
        assertEquals(setOf("unranked_label"), ids(listOf(word("Unranked"))))
    }

    @Test fun lowOrMissingOcrConfidenceCannotBecomeEvidence() {
        assertTrue(ids(listOf(word("Warehouse", .49f), word("Airplane", -1f))).isEmpty())
        assertTrue(ids(listOf(word("Ranked", Float.NaN), word("Arena", 1.1f))).isEmpty())
    }

    @Test fun ambiguousHazardsAndModeConflictsKeepActualConfidence() {
        val cues = PubgCueExtractor.extract(scoreboard() + listOf(
            word("Warehouse", .99f), word("Airplane", .75f, top = .4f),
            word("Training", .65f, left = .1f),
        ), false).associateBy { it.id }
        assertEquals(.75f.toDouble(), cues.getValue("airplane").confidence, .000001)
        assertEquals(.65f.toDouble(), cues.getValue("training_label").confidence, .000001)
        assertEquals(.99f.toDouble(), cues.getValue("warehouse_label").confidence, .000001)
        assertTrue("score_hud" in cues)
    }

    @Test fun oneTrainingRangeBannerCannotBecomeTwoIndependentSafeGroups() {
        val cues = ids(listOf(word("Training Shooting Range", top = .4f)))
        assertTrue("target_practice" in cues)
        assertFalse("training_label" in cues)
    }

    @Test fun malformedBoundsAndNamesInBottomControlsAreIgnored() {
        assertTrue(ids(listOf(word("Warehouse", top = .88f))).isEmpty())
        assertTrue(ids(listOf(word("Ranked", left = -0.2f))).isEmpty())
        assertTrue(ids(listOf(word("Training", right = .2f))).isEmpty())
    }

    @Test fun scoreboardRequiresTwoDistinctNumericBoxesAndAnUpperTimer() {
        assertEquals(setOf("score_hud", "round_timer"), ids(scoreboard()))
        assertFalse("score_hud" in ids(scoreboard().take(2)))
        assertFalse("score_hud" in ids(listOf(word("17 23"), word("08:42", top = .18f))))
        assertFalse("score_hud" in ids(scoreboard().map { it.copy(top = .7f, bottom = .74f) }))
        assertFalse("score_hud" in ids(listOf(word("17", left = .01f), word("23", left = .14f), word("08:42"))))
    }

    @Test fun respawnRequiresARealCentralCountdownAndTransitionsNeedNewHud() {
        val countdown = listOf(word("Respawn in", top = .45f), word("3", left = .49f, top = .51f))
        assertTrue("respawn_countdown" in ids(countdown))
        assertFalse("respawn_countdown" in ids(countdown.take(1)))
        assertFalse("respawn_countdown" in ids(countdown.map { it.copy(left = .01f, right = .1f) }))
        assertTrue("respawn_transition" in ids(scoreboard(), previousRespawn = true))
        assertFalse("respawn_transition" in ids(scoreboard()))
        assertFalse("respawn_transition" in ids(listOf(word("Warehouse")), previousRespawn = true))
        assertFalse("respawn_transition" in ids(scoreboard() + countdown, previousRespawn = true))
    }

    @Test fun ordinaryCombatJumpAndFollowAreNotBattleRoyaleCues() {
        assertTrue(ids(listOf(word("Jump", top = .8f), word("Follow", top = .5f))).isEmpty())
        assertTrue("jump" in ids(listOf(word("Jump", top = .75f), word("Airplane", top = .5f))))
        assertTrue("follow" in ids(listOf(word("Follow", top = .75f), word("Flight Path"))))
    }

    @Test fun multiwordFlightPhrasesMustBeSpatiallyContiguous() {
        assertTrue("flight_path" in ids(listOf(word("Flight Path"))))
        assertTrue("flight_path" in ids(listOf(word("Flight", left = .3f), word("Path", left = .39f))))
        assertFalse("flight_path" in ids(listOf(word("Flight", left = .1f), word("Path", left = .8f))))
        assertFalse("flight_path" in ids(listOf(word("Flight avoidance Path"))))
        assertFalse("flight_path" in ids(listOf(
            word("Flight", left = .3f), word("avoidance", left = .385f, right = .40f),
            word("Path", left = .41f),
        )))
        assertFalse("free_fall" in ids(listOf(word("Free", top = .3f), word("Fall", top = .8f))))
        assertTrue("free_fall" in ids(listOf(word("Free Fall", top = .4f))))
    }

    @Test fun battleRoyaleLabelsAndCabinIndicatorsAreImmediateObservedCues() {
        assertTrue("airplane" in ids(listOf(word("Players in cabin", top = .08f))))
        assertTrue("br_map" in ids(listOf(word("Erangel"))))
        assertTrue("ranked_label" in ids(listOf(word("Ranked"))))
        assertTrue("parachute" in ids(listOf(word("Parachute", top = .7f))))
    }

    @Test fun confidenceIsMinimumActualSupportingOcrConfidence() {
        val cues = PubgCueExtractor.extract(listOf(
            word("Flight", .91f, left = .3f), word("Path", .83f, left = .39f),
        ), false)
        val cue = cues.single { it.id == "flight_path" }
        assertEquals(.83f.toDouble(), cue.confidence, .000001)
        assertEquals("top_hud", cue.region)
        assertEquals("flight_path", cue.toMap()["id"])
    }

    @Test fun trainingAndTdmPhrasesHaveIndependentSpatialEvidence() {
        assertTrue("tdm_label" in ids(listOf(word("Team Deathmatch"))))
        assertTrue("training_controls" in ids(listOf(word("Training Assistant", top = .65f))))
        assertTrue("target_practice" in ids(listOf(word("Target Practice", top = .4f))))
        assertFalse("training_controls" in ids(listOf(word("Training Assistant", top = .1f))))
    }

    @Test fun trainingAssistantCannotAlsoServeAsIndependentModeIdentity() {
        assertEquals(setOf("training_controls"), ids(listOf(word("Training Assistant", top = .65f))))
        assertEquals(setOf("training_controls"), ids(listOf(
            word("Training", left = .30f, top = .65f),
            word("Assistant", left = .39f, top = .65f),
        )))
        assertTrue(ids(listOf(word("Training Assistant", top = .1f))).isEmpty())
        assertEquals(setOf("training_controls"), ids(listOf(word("Training Reset Target", top = .65f))))
        assertEquals(setOf("training_label", "training_controls"), ids(listOf(
            word("Training Ground", top = .10f), word("Training Assistant", top = .65f),
        )))
    }
}
