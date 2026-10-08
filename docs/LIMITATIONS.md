# Capability and evidence boundaries

| Requested capability | Implemented source / boundary |
| --- | --- |
| Manufacturer, model, OS | Public Android/iOS APIs; iOS hardware identifiers may be more specific than the human-readable model name |
| Screen dimensions and density | Public display/view metrics; pixels, logical dimensions, and scale are labeled separately |
| Refresh rate | Public available/current display information where supplied by the OS; never equate this with PUBG FPS |
| Touch sampling rate | `UNKNOWN`; pointer events inside SPIDER AIM cannot establish hardware sampling frequency or PUBG touch latency |
| Gyroscope | Policy always disabled; device capability, when reported, does not enable gyro calibration |
| Battery / charging | Official device-wide readings; do not attribute all drain to PUBG or SPIDER AIM |
| Thermal state | Coarse official OS thermal state when supported; not a fabricated CPU/GPU temperature |
| CPU/GPU load and PUBG FPS | Unavailable unless a legitimate provider supplies them; no other-process inspection |
| App workload | Android reports this process's CPU time and memory; capture is limited to one local OCR job at a time at a two-second minimum interval and stops on severe heat; physical-device overhead and per-app wattage remain unmeasured |
| Settings reading/applying | Manual entry and manual official PUBG UI application; no public integration supplied |
| Complete backups | All settings recorded in SPIDER AIM; cannot include unobservable game files/settings |
| One-tap restore | Restores SPIDER AIM data immediately; values still require manual restoration in PUBG |
| Mode detection | Android MediaProjection + UsageStats foreground checks + bundled Latin ML Kit OCR feed a fail-closed temporal recognizer; no official PUBG telemetry/API. Manual historical buttons never grant permission |
| Floating entry/review panel | Optional Android `SYSTEM_ALERT_WINDOW` special access creates a `TYPE_APPLICATION_OVERLAY` panel; it uses the existing guarded workflow and cannot control PUBG or grant a safe mode. Physical-device window/keyboard/secure-capture behavior is not yet validated |
| Aim and tracking evidence | Player-entered repeated observations tied to device/weapon/scope/attachments/distance; not an automatic trained vision system |
| Hit registration | Differential diagnosis from available evidence; actual server hit decisions and desync cannot be independently established |
| Death review | Structured observations and repeated-pattern analysis, not automatic recent-video capture |
| Passive background capture | Android consented MediaProjection foreground service samples mode cues only; requires Usage Access and verified foreground PUBG. No high-resolution continuous video recording or complete automatic aim/death analyzer |
| Throwable visibility | Official visible trajectory/camera/control usability observations; no obstacle transparency |
| Landing guidance | Retrospective geometric estimate using user-supplied data; no live `JUMP NOW`, map feed, invented PUBG flight constants, or automatic control |
| Notifications | Proposal notices remain in-app, with no push service. Android capture has the required foreground-service notification and stop action |
| iOS | Device APIs/UI sources exist, but PUBG cross-app screen capture is not implemented. It requires ReplayKit Broadcast Upload Extension and Apple provisioning. Automatic authorization stays blocked; macOS/Xcode/signing and real-device tests remain separate |
| Emulator exclusion | Native physical-device checks are best-effort platform signals; they are not anti-tamper attestation |

## Interpretation of results

The six mode states are `TRAINING_SAFE`, `WAREHOUSE_SAFE`, `ARENA_SAFE`, `SAFE_UNRANKED`, `COMPETITIVE_BLOCKED`, and `UNKNOWN_BLOCKED`. A safe result needs four distinct frames spanning at least six seconds with a minimum 0.95 heuristic score and evidence younger than 12 seconds. A Ranked/Battle Royale indicator at 0.80 or above locks the capture session immediately. There is no manual safe override; ambiguity, missing permissions, or unverified foreground are blocked.

The OCR adapter uses Latin text and conservative HUD regions. Unsupported Arabic game text, custom layouts, absent labels, low OCR confidence, frozen frames, or unusual aspect ratios may remain `UNKNOWN_BLOCKED` indefinitely. Real PUBG screen/layout evaluation has not established sensitivity, specificity, or false-unlock rates. The displayed confidence is an evidence score, not a measured probability. It must not be described as 95% demonstrated accuracy.

The capture service limits the long edge to 960 pixels and duty-cycles display sampling at most once per two seconds, with one in-flight OCR job. Competitive latching shuts down pixel/OCR work while retaining the service/session stop notification. Its pixel fingerprints reject repeated frames, but are not cryptographic attestation that an image originated from a particular game mode. UsageStats is an OS foreground signal, not game telemetry. Android 14 requests full-display capture to avoid unrelated selected-window evidence.

Returning to the main SPIDER AIM activity still closes its form guard because PUBG is no longer verified foreground. The optional Android floating panel supplies a separate authorized interaction path using the same existing workflow while PUBG remains foreground. Its permission cannot unlock the guard; native capture proof and Dart authorization are both required. The secure window is excluded from OCR evidence; if a device blanks capture or the panel covers needed HUD evidence, forms close without a bypass. Real phone/tablet validation of layout, keyboard, rotation, secure capture, and foreground checks is still required. See [Overlay](OVERLAY.md).

Images and full OCR strings remain transient in native memory, are released after processing, and are not written to the database or sent to a server. Existing session/settings records remain local. No Accessibility control, private API, root, or jailbreak is used.

Manual inputs may contain measurement or recall errors. Use several comparable trials, keep distance and equipment consistent, and record the source of FPS/ping/thermal observations. Missing information is missing information, not evidence of a healthy system. Correlation between a death and heat or ping is an indicator, not proof of causality.

Stable aim and more observed hits in a test may justify a user-approved setting trial. They do not guarantee future results or alter the server's rules. When evidence is insufficient or conflicting, the diagnosis remains `INCONCLUSIVE`.

Battery drain per hour is a device-wide estimate and is unreliable for very short sessions, charging intervals, or coarse battery-percent readings. A report must identify these cases rather than assigning precise per-app consumption. Any predicted battery savings without measured baseline evidence must remain unknown.

The current battery UI records session start and end snapshots. Intermediate heat peaks, charging, or workload changes are not continuously sampled. A report's worst thermal state means the worst **observed reading**, not necessarily the hottest point of the whole session.

## Release verification

Local commands and GitHub Actions logs are the evidence of build validity. Do not report `flutter analyze`, `flutter test`, or APK build as passed unless they actually completed successfully. iOS compilation, store signing, physical-device thermal/FPS overhead, game-mode verification, and actual coaching effectiveness are separate acceptance tests.

APK signing currently uses the development configuration. The previous APK from run `37723093465` and current APK from run `37736827044` have different public signing certificates, so these artifacts cannot update one another in place. Preserve the installed app if stored data exists or is uncertain; the previous version has no data-export feature, and its recorded backups remain inside its own application data. A stable private release key prevents future mismatches but cannot make a differently signed APK replace that existing installation. No private signing material belongs in the repository. See [VERIFICATION.md](VERIFICATION.md) for the compared public certificate fingerprints.

Version `1.0.1+2`, code revision `f4fdde7728e573258b308824b57893fb47278d7e`, passed analysis, 214 Flutter tests, Android APK compilation, the native test task, and the actual APK network-permission audit in [run 37736827044](https://github.com/abbady110/spider-aim-/actions/runs/37736827044). The built APK permission output includes `SYSTEM_ALERT_WINDOW` and excludes `INTERNET` and `ACCESS_NETWORK_STATE`. The previous 184-test and 111-test results are historical. Real-device recognition, floating-panel/keyboard/secure-capture behavior, and performance acceptance remain outstanding; see [VERIFICATION.md](VERIFICATION.md) for revision-specific evidence and remaining checks.

Official API references: [MediaProjection](https://developer.android.com/media/grow/media-projection), [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager), and [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).
