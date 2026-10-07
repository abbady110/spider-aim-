# Architecture

SPIDER AIM separates observations, analysis, proposals, and approval. No analysis engine writes to PUBG or activates an input-control mechanism.

## Data flow

```text
Official OS APIs / manually recorded test observations
                         |
                 provenance + validation
                         |
       game-mode guard + NON_GYRO input policy
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
| Game mode guard | Block Ranked and unknown contexts; distinguish manual review from verified live operations |
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

## Extension boundaries

Future on-device observation providers must report source, quality, missing data, timestamps, and calibration context. A live provider must additionally prove a currently safe Unranked mode and immediately revoke that proof on uncertainty or transition. A manual declaration cannot satisfy that live contract.

Screen capture requires official Android MediaProjection or Apple ReplayKit consent and a separately implemented platform lifecycle. No capture permission is requested until a real, safe provider exists. No provider may inject touch, inspect another application's memory, change game files, bypass walls, or manipulate network traffic.

Future statistical or learned models must preserve evidence provenance and the same approval/backup state machine. Add models only with real evaluation data; avoid presenting heuristic scores as server-confirmed game telemetry.

## Build

Flutter targets Android and iOS only. Android CI uses pinned Flutter 3.35.7 and Java 17, then analysis, tests, and a release-mode ARM/ARM64 APK. Missing Gradle wrapper tooling and Xcode project/assets are generated safely by `scripts/bootstrap_flutter.sh`; tracked native sources are never replaced by a fresh project scaffold. Android application ID is `org.spideraim.coach`. The generated iOS bundle identifier must be set to the owner's chosen registered identifier when provisioning a signed iOS release.
