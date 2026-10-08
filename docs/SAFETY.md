# Safety and integrity contract

## Runtime rules

- `NON_GYRO` and `TOUCH_ONLY` are profile invariants. No calibration suggestion enables gyroscope or ADS gyroscope.
- `COMPETITIVE_BLOCKED` and `UNKNOWN_BLOCKED` reject calibration, trials, analysis, settings mutations, and landing assistance. Battle Royale is blocked even if the player labels it Unranked.
- Only automatically recognized `TRAINING_SAFE`, `WAREHOUSE_SAFE`, `ARENA_SAFE`, or `SAFE_UNRANKED` can authorize an operation. Manual historical labels are read-only and cannot override the guard. The legacy declaration method grants no permission.
- Authorized capture is necessary but insufficient: foreground PUBG verification, independent safe cues, four distinct frames across six seconds, and a heuristic score of at least 0.95 are required. Safe evidence expires after 12 seconds.
- Any credible Ranked/Battle Royale cue at confidence 0.80 or above immediately latches the competitive lock and shuts down pixel/OCR processing, retaining the session/service stop notification. Ambiguity is `UNKNOWN_BLOCKED`; missing danger indicators do not establish safety.
- Capture revocation, stale/frozen frames, unverified foreground, and capture errors revoke safe authorization. Every mutable workflow checks authorization inside the storage transaction as well as before it. Final approval is blocked if capture authority disappears after a passing test.
- Every settings proposal requires repeated evidence, a reason, uncertainty, current/proposed values, expected effect, and tradeoffs.
- User consent to a trial is required before a candidate is created. A complete local recorded-settings backup must exist before the candidate becomes active.
- Testing does not overwrite the approved snapshot. A real recorded Unranked comparison and distinct final user approval are required.
- Aim stability and observed hit outcomes take priority; a sensitivity speed increase alone cannot establish success. Regressions in key performance/thermal/battery metrics must be considered, and missing data must not be fabricated.
- Restore restores SPIDER AIM's snapshot and supplies PUBG manual-restore instructions. It never claims to have changed the game.
- Battery adaptation reduces SPIDER AIM workload. It does not change PUBG graphics, FPS, refresh rate, or touch responsiveness.

## Prohibited capabilities

The app has no aiming/movement actuator, touch injection, accessibility automation, memory/process injection, game-file editing, packet manipulation, damage changes, enemy tracking, ESP, wall/rock transparency, automatic recoil compensation, or parachute control. A future feature adding one of these violates the architecture, regardless of whether it is named calibration.

Only public platform APIs are permitted. Device data with no reliable API is reported as unavailable. PUBG FPS is distinct from Flutter rendering FPS, and estimated app workload is distinct from measured power consumed by another process.

## Capture and privacy

Android uses official MediaProjection consent and a non-exported `mediaProjection` foreground service with a stop notification, requesting notification permission on Android 13+ where needed. Android 14 requests full-display capture to avoid analyzing an unrelated selected window. Foreground verification uses `UsageStatsManager` only after the user grants special Usage Access in Android settings. Screen/Usage Access denial or revocation remains a block; neither permission changes PUBG or provides access to its memory.

Bundled ML Kit Latin OCR processes low-resolution frames locally at a two-second minimum interval. Raw pixels and OCR strings are not persisted, logged, or uploaded. Only semantic evidence is delivered in-process to the guard. The capture path runs at most one OCR task at a time and stops on severe heat. No automatic game graphics/FPS/refresh/touch reduction is permitted.

No cross-app capture is implemented on iOS. The guard stays closed until a future ReplayKit Broadcast Upload Extension, Apple provisioning, and appropriate validation provide a legitimate source. Manual buttons cannot replace missing platform support.

Returning to the main SPIDER AIM activity closes its form guard. The optional Android floating panel uses explicit official overlay special access while PUBG remains foreground. Native session/temporal/foreground proof and the Dart guard authorize every action; permission alone never unlocks it. Secure overlay contents cannot become OCR evidence. Revocation closes forms and prevents submission. The existing controller remains the sole workflow/database writer; no game input is injected. See [Overlay](OVERLAY.md) for usage and physical-device acceptance requirements.

## Test expectations

Behavioral tests cover automatic-only authorization, failed manual overrides in unknown/competitive states, confidence/temporal/foreground requirements, revocation, blocked mode attempts, approval ordering, backup preconditions, transactional rollback, restart recovery, rejection, restore, final approval prerequisites, device isolation, NON_GYRO enforcement, and battery policy. Synthetic screen fixtures exercise the real recognizer; they do not override the guard. Widget tests check Arabic RTL and that actions follow the workflow.

These tests validate application logic. They do not prove real-world OCR/HUD recognition accuracy, physical-device performance, aim improvement, server hit registration, or official certification by PUBG. Confidence is heuristic, and real HUD/locale/device validation remains pending. Unsupported Arabic/layouts stay unknown. See [Verification](VERIFICATION.md) for the actual build and test revision.
