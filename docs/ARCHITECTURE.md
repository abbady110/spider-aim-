# Architecture

SPIDER AIM separates observations, analysis, proposals, and approval. No analysis engine writes to PUBG or activates an input-control mechanism.

## Data flow

```text
Android consent + Usage Access
             |
MediaProjection foreground service / verified PUBG foreground
             |
low-resolution local Latin OCR / semantic cues + pixel fingerprints
             |
automatic temporal recognition --> COMPETITIVE / UNKNOWN: block
             |
fresh recognized safe mode + NON_GYRO input policy
             |
Official device APIs / player-recorded coaching observations
                         |
    aim / movement / throwables / diagnostic engines
                         |
                 evidence-based proposal
                         |
              explicit approval for trial
                         |
         atomic local backup + testing candidate
                         |
       manual apply in PUBG + Unranked comparison
                         |
                  final user approval
```

## Module responsibilities

| Area | Responsibility |
| --- | --- |
| Core models and policies | Validated settings, NON_GYRO policy, evidence provenance, immutable snapshots |
| `game_mode_guard/` | Sole authorization boundary; six modes, no manual override, guard rechecks for every mutable operation |
| `game_mode_recognition/` | Validate captured evidence, distinct frames, timestamps, foreground, confidence, contradictions, and session-latched competition |
| `capture/` and Android native capture | Official consent/lifecycle bridge, visible foreground service, UsageStats foreground verification, bundled local Latin OCR |
| Calibration and profiles | Compare repeated observations within one device and weapon/scope/attachments/distance context |
| Aim / hit registration | Prioritize stable aim and observed hits, retain uncertainty, identify performance/network confounders |
| Movement / throwables | Score player-provided tests of official control settings and offer manual practice guidance |
| Death analysis | Aggregate repeated patterns; do not infer sensitivity from every death |
| Battery / thermal | Official observations and session reports; reduce only SPIDER AIM's own workload |
| Landing | Explainable geometry from manually supplied positions and measured descent assumptions |
| Versions / backups / testing | Transactional approval state machine and immutable full recorded-settings backups |
| Storage | SQLite schema/version migrations and crash-safe durable transactions |
| Native device bridge | Android/iOS public APIs; unsupported readings remain null/unknown |
| UI | Arabic RTL material interface and explicit approval, rejection, retest, and restore actions |

## State and integrity

The approved snapshot, trial candidate, and backup are separate entities. Trial approval is not final approval. Creating a trial must preserve its complete previous recorded-settings snapshot before it can become active. Transaction rollback prevents half-created trials on failure. Restart restores persisted approved and trial identities rather than promoting the trial.

The lifecycle records proposed, approved-for-test, backed-up, testing, passed/failed, final approval, rejection, and rollback decisions. The state machine, not an enabled UI button alone, enforces prerequisite checks. History and backups are retained; no casual backup-delete operation is exposed.

Every profile is device-specific. A tablet receives its own starting settings; model matching never authorizes copying sensitivity from another device. Weapon identifiers and scopes are extensible data rather than a universal sensitivity table.

## Automatic authorization

`GameModeGuard` delegates all decisions to `AutomaticModeRecognizer`. Its exact states are `TRAINING_SAFE`, `WAREHOUSE_SAFE`, `ARENA_SAFE`, `SAFE_UNRANKED`, `COMPETITIVE_BLOCKED`, and `UNKNOWN_BLOCKED`. `declareOfflineMode` is a compatibility no-op; historical selections may update read-only display context, never the decision. Permission is checked both before entering and inside a settings write transaction.

The Android capture service duty-cycles its display sampling at most once per two seconds with a maximum 960-pixel long edge and one in-flight OCR task. It verifies the foreground package using user-granted Usage Access both before OCR and after OCR completes. Android 14 uses full-display consent configuration to avoid an unrelated selected-app window. Bundled ML Kit Latin recognition produces bounded semantic cues; pixels and full OCR text remain transient native memory. Flutter receives cue IDs, confidence, regions, a pixel-derived fingerprint, timestamp, sequence, and capture-session identity. No raw video/text is stored or uploaded.

Safe recognition requires at least four distinct frame fingerprints, monotonically increasing sequence/timestamps, a six-second minimum span, independent consistent cues, and a score at least 0.95. Evidence expires at 12 seconds. A credible competitive/Battle Royale indicator at confidence 0.80 or above latches `COMPETITIVE_BLOCKED` immediately and stops pixel/OCR work while retaining the service/session stop notification. Contradictory or insufficient evidence yields `UNKNOWN_BLOCKED`; absence of a danger cue is never positive evidence of safety. Stopping capture, losing consent, an unverified foreground, or stale frames cannot preserve safe authorization.

Confidence is a conservative heuristic score, not measured classification probability. Real PUBG HUD layouts, devices, and locales still need validation. Latin-only detection cannot establish safety from unsupported Arabic text/layouts. The recognizer only classifies modes; aim/death metrics remain structured manual observations.

The app-resume path closes form authorization when the user returns to SPIDER AIM. Interactive writes while PUBG remains foreground are not currently available. A future authorized overlay or verified session-review interaction must solve that usability constraint without weakening the guard or treating manual labels as proof.

## Extension boundaries

Future on-device aim/death observation providers must report source, quality, missing data, timestamps, and calibration context. They must use the same automatic authorization boundary and revoke work on uncertainty or transition. A manual declaration cannot satisfy this contract.

Android screen capture uses the implemented official MediaProjection lifecycle and foreground service, with no Accessibility automation. The source allows only `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `POST_NOTIFICATIONS`, and special-access `PACKAGE_USAGE_STATS` declarations. Notification consent is requested on Android 13+ where needed; it does not imply screen-capture consent. There is no source-declared Internet permission or cloud OCR provider. Severe thermal state stops capture workload before changing any PUBG setting.

iOS cross-app capture is not implemented. Adding it requires an authorized ReplayKit Broadcast Upload Extension, provisioning, cross-extension data transport, and real-device validation. An in-app replay recorder would not by itself provide PUBG screen access. The current iOS path reports capture unavailable and stays fail-closed. No provider may inject touch, inspect another app's memory, change game files, bypass walls, or manipulate network traffic.

Future statistical or learned models must preserve evidence provenance and the same approval/backup state machine. Add models only with real evaluation data; avoid presenting heuristic scores as server-confirmed game telemetry.

Official API references: [MediaProjection](https://developer.android.com/media/grow/media-projection), [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager), and [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).

## Build

Flutter targets Android and iOS only. Android CI uses pinned Flutter 3.35.7 and Java 17, then analysis, Flutter tests, a release-mode ARM/ARM64 APK, and `:app:testReleaseUnitTest` native capture tests before artifact upload. Missing Gradle wrapper tooling and Xcode project/assets are generated safely by `scripts/bootstrap_flutter.sh`; tracked native sources are never replaced by a fresh project scaffold. Android application ID is `org.spideraim.coach`. The generated iOS bundle identifier must be set to the owner's registered identifier when provisioning a signed iOS release.
