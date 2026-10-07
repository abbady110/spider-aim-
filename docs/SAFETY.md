# Safety and integrity contract

## Runtime rules

- `NON_GYRO` and `TOUCH_ONLY` are profile invariants. No calibration suggestion enables gyroscope or ADS gyroscope.
- `RANKED_BLOCKED` and `UNKNOWN_BLOCKED` reject calibration, trials, live analysis, and landing assistance.
- A manually declared historical Unranked session can support manual review only. It does not verify another app's current game mode. Live analysis stays disabled without a reliable verifier.
- Every settings proposal requires repeated evidence, a reason, uncertainty, current/proposed values, expected effect, and tradeoffs.
- User consent to a trial is required before a candidate is created. A complete local recorded-settings backup must exist before the candidate becomes active.
- Testing does not overwrite the approved snapshot. A real recorded Unranked comparison and distinct final user approval are required.
- Aim stability and observed hit outcomes take priority; a sensitivity speed increase alone cannot establish success. Regressions in key performance/thermal/battery metrics must be considered, and missing data must not be fabricated.
- Restore restores SPIDER AIM's snapshot and supplies PUBG manual-restore instructions. It never claims to have changed the game.
- Battery adaptation reduces SPIDER AIM workload. It does not change PUBG graphics, FPS, refresh rate, or touch responsiveness.

## Prohibited capabilities

The app has no aiming/movement actuator, touch injection, accessibility automation, memory/process injection, game-file editing, packet manipulation, damage changes, enemy tracking, ESP, wall/rock transparency, automatic recoil compensation, or parachute control. A future feature adding one of these violates the architecture, regardless of whether it is named calibration.

Only public platform APIs are permitted. Device data with no reliable API is reported as unavailable. PUBG FPS is distinct from Flutter rendering FPS, and estimated app workload is distinct from measured power consumed by another process.

## Test expectations

Behavioral tests cover blocked mode attempts, approval ordering, backup preconditions, transactional rollback, persistence across restart, rejection, restore, final approval prerequisites, independent device profiles, NON_GYRO enforcement, and the battery recommendation policy. Widget tests check Arabic RTL and that actions follow the workflow.

These tests validate application behavior. They do not prove physical-device performance, real-world aim improvement, current PUBG server hit registration, or official game-mode detection. Those require separate real-device evaluation with player consent and official in-game observations.
