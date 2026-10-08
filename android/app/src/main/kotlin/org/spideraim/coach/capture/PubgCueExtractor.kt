package org.spideraim.coach.capture

import java.util.Locale
import kotlin.math.abs

/** OCR bounds are normalized to the full captured screen, never to an OCR crop. */
data class OcrWord(
    val text: String,
    val confidence: Float,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
)

data class ScreenCue(val id: String, val confidence: Double, val region: String) {
    fun toMap(): Map<String, Any> = mapOf(
        "id" to id,
        "confidence" to confidence,
        "region" to region,
    )
}

/**
 * Conservative Latin OCR adapter. Cues describe observed UI, not a safe mode decision.
 * The temporal GAME_MODE_GUARD makes that decision across several captured frames.
 * All confidence values come from supporting OCR words; no label creates a HUD cue.
 */
object PubgCueExtractor {
    // Preserve uncertain conflicts for the guard's UNKNOWN decision. This does
    // not lower the guard's >=.95 safe proof or >=.80 competitive latch thresholds.
    private const val MIN_CONFIDENCE = 0.50f
    private val tokenPattern = Regex("[A-Z0-9]+(?::[0-9]{2})?")
    private val integerPattern = Regex("[0-9]{1,2}")
    private val timerPattern = Regex("[0-9]{1,2}:[0-5][0-9]")

    private data class Token(val text: String, val word: OcrWord, val source: Int, val position: Int) {
        val x: Float get() = (word.left + word.right) / 2
        val y: Float get() = (word.top + word.bottom) / 2
    }

    fun extract(words: List<OcrWord>, previousRespawn: Boolean): List<ScreenCue> {
        val tokens = words.flatMapIndexed { index, word ->
            if (!credible(word)) emptyList() else tokenPattern
                .findAll(word.text.uppercase(Locale.ROOT))
                .mapIndexed { position, match -> Token(match.value, word, index, position) }.toList()
        }
        val cues = linkedMapOf<String, ScreenCue>()
        fun emit(id: String, support: List<Token>, region: String) {
            if (support.isEmpty()) return
            val cue = ScreenCue(id, support.minOf { it.word.confidence }.toDouble(), region)
            val existing = cues[id]
            if (existing == null || cue.confidence > existing.confidence) cues[id] = cue
        }
        fun label(id: String, vararg alternatives: String) {
            alternatives.forEach { alternative ->
                phrase(tokens, alternative).filter { it.all(::inModeLabel) }
                    .forEach { emit(id, it, "mode_label") }
            }
        }

        val trainingControlGroups = listOf("TRAINING ASSISTANT", "RESET TARGET", "TARGET SETTINGS")
            .flatMap { phrase(tokens, it) }
        val targetPracticeGroups = listOf("TARGET PRACTICE", "SHOOTING RANGE")
            .flatMap { phrase(tokens, it) }
        val trainingActivitySources = (trainingControlGroups + targetPracticeGroups)
            .flatten().map { it.source }.toSet()
        // A Training Assistant button is one observation, not both mode identity
        // and an independent training control. Exclude its entire OCR element,
        // including cases where ML Kit joins button text into one element.
        listOf("TRAINING", "TRAINING GROUND", "TRAINING GROUNDS").forEach { name ->
            phrase(tokens, name).filter { group ->
                group.all(::inModeLabel) && group.none { it.source in trainingActivitySources }
            }.forEach { emit("training_label", it, "mode_label") }
        }
        label("warehouse_label", "WAREHOUSE")
        label("arena_label", "ARENA")
        label("tdm_label", "TDM", "TEAM DEATHMATCH")
        label("unranked_label", "UNRANKED")
        label("ranked_label", "RANKED", "COMPETITIVE")
        label("br_map", "CLASSIC", "ERANGEL", "MIRAMAR", "SANHOK", "VIKENDI", "LIVIK", "RONDO", "NUSA")

        // Two distinct score boxes are required; a single OCR string or mode name
        // cannot manufacture both halves of a scoreboard.
        val scores = tokens.filter {
            integerPattern.matches(it.text) && it.y <= 0.23f && it.x in 0.24f..0.76f
        }
        val scorePair = scores.asSequence().flatMap { a ->
            scores.asSequence().filter { b ->
                a.source != b.source && a.x < b.x && b.x - a.x in 0.035f..0.35f &&
                    abs(a.y - b.y) <= 0.045f
            }.map { b -> listOf(a, b) }
        }.maxByOrNull { pair -> pair.minOf { it.word.confidence } }
        val timers = tokens.filter {
            timerPattern.matches(it.text) && it.y <= 0.34f && it.x in 0.25f..0.75f
        }
        val scoreboardTimer = if (scorePair == null) null else timers.filter { timer ->
            abs(timer.x - scorePair.map { it.x }.average()) <= 0.15 &&
                abs(timer.y - scorePair.first().y) <= 0.20f
        }.maxByOrNull { it.word.confidence }
        if (scorePair != null && scoreboardTimer != null) {
            emit("score_hud", scorePair + scoreboardTimer, "top_hud")
            emit("round_timer", listOf(scoreboardTimer), "top_hud")
        }

        listOf("TARGET PRACTICE", "SHOOTING RANGE").forEach { name ->
            phrase(tokens, name).filter { group -> group.all { it.y <= 0.72f } }
                .forEach { emit("target_practice", it, "center") }
        }
        trainingControlGroups.filter { group -> group.all { it.y >= 0.35f } }
            .forEach { emit("training_controls", it, "bottom_controls") }

        val respawnWords = tokens.filter {
            it.text in setOf("RESPAWN", "RESPAWNING") && inCenter(it)
        }
        val respawnSupport = respawnWords.mapNotNull { respawn ->
            val number = tokens.filter { number ->
                integerPattern.matches(number.text) && number.text.toInt() in 1..30 &&
                    inCenter(number) && abs(number.x - respawn.x) <= 0.22f &&
                    abs(number.y - respawn.y) <= 0.13f
            }.maxByOrNull { it.word.confidence }
            number?.let { listOf(respawn, it) }
        }.maxByOrNull { group -> group.minOf { it.word.confidence } }
        if (respawnSupport != null) emit("respawn_countdown", respawnSupport, "center")
        if (previousRespawn && respawnWords.isEmpty() && scorePair != null && scoreboardTimer != null) {
            emit("respawn_transition", scorePair + scoreboardTimer, "top_hud")
        }

        listOf("AIRPLANE", "AIRCRAFT", "PLAYERS IN CABIN", "REMAINING IN CABIN").forEach { name ->
            phrase(tokens, name).filter { group -> group.all { it.y <= 0.72f } }
                .forEach { emit("airplane", it, "top_hud") }
        }
        phrase(tokens, "FLIGHT PATH").filter { group -> group.all { it.y <= 0.65f } }
            .forEach { emit("flight_path", it, "top_hud") }
        listOf("FREE FALL", "FREEFALL").forEach { name ->
            phrase(tokens, name).filter { group -> group.all { it.y in 0.15f..0.92f } }
                .forEach { emit("free_fall", it, "center") }
        }
        tokens.filter { it.text == "PARACHUTE" && it.y in 0.15f..0.95f }
            .forEach { emit("parachute", listOf(it), "center") }

        // JUMP is also a combat button; FOLLOW can be a generic squad action.
        // Neither is BR evidence unless genuine flight text corroborates it.
        val flightTokens = tokens.filter {
            it.text in setOf("AIRPLANE", "AIRCRAFT", "CABIN", "PARACHUTE", "ALTITUDE", "FLIGHT")
        }
        tokens.filter { it.text in setOf("JUMP", "FOLLOW", "FOLLOWING", "UNFOLLOW") }.forEach { action ->
            val nearby = flightTokens.filter {
                abs(it.x - action.x) <= 0.40f && abs(it.y - action.y) <= 0.32f
            }.maxByOrNull { it.word.confidence }
            val flightCue = cues["airplane"] ?: cues["flight_path"]
            if (nearby != null) {
                emit(if (action.text == "JUMP") "jump" else "follow", listOf(action, nearby), "center")
            } else if (flightCue != null) {
                val confidence = minOf(action.word.confidence.toDouble(), flightCue.confidence)
                val id = if (action.text == "JUMP") "jump" else "follow"
                cues[id] = ScreenCue(id, confidence, "center")
            }
        }
        return cues.values.toList()
    }

    private fun credible(word: OcrWord): Boolean = word.confidence.isFinite() &&
        word.confidence in MIN_CONFIDENCE..1f &&
        listOf(word.left, word.top, word.right, word.bottom).all { it.isFinite() && it in 0f..1f } &&
        word.left < word.right && word.top < word.bottom

    private fun inModeLabel(token: Token): Boolean = token.y <= 0.35f ||
        (token.x in 0.15f..0.85f && token.y in 0.35f..0.70f)

    private fun inCenter(token: Token): Boolean = token.x in 0.15f..0.85f && token.y in 0.23f..0.78f

    /** Matches whole tokens in reading order on one visual line, including ML Kit
     * elements containing several words. Spatially separated words never join. */
    private fun phrase(tokens: List<Token>, text: String): List<List<Token>> {
        val wanted = text.split(' ')
        val matches = mutableListOf<List<Token>>()
        fun extend(group: List<Token>, next: Int) {
            if (next == wanted.size) {
                matches += group
                return
            }
            val previous = group.last()
            tokens.filter { candidate ->
                candidate.text == wanted[next] && candidate !in group &&
                    abs(candidate.y - previous.y) <= 0.045f &&
                    (if (candidate.source == previous.source) {
                        candidate.position == previous.position + 1
                    } else {
                        candidate.position == 0 &&
                            tokens.none { it.source == previous.source && it.position > previous.position } &&
                            candidate.word.left >= previous.word.right &&
                            candidate.word.left - previous.word.right <= 0.09f &&
                            tokens.none { between ->
                                between.source != previous.source && between.source != candidate.source &&
                                    abs(between.y - previous.y) <= 0.045f &&
                                    between.x > previous.x && between.x < candidate.x
                            }
                    })
            }.forEach { extend(group + it, next + 1) }
        }
        tokens.filter { it.text == wanted.first() }.forEach { extend(listOf(it), 1) }
        return matches
    }
}
