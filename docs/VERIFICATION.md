# Verification status / حالة التحقق

Current source review date: **2026-10-08 (UTC)**.

## Floating-panel revision: verification pending

The authorized Android floating panel has been added to address the foreground interaction gap. Its new Dart/native/permission/UI tests and APK build require a fresh CI run. The verified results below belong to code revision `5f006469` before the panel was added; they do not establish compilation or device behavior of the new panel. Current offline structural checks pass, but physical-device overlay/keyboard/secure-capture acceptance has not been run.

نجح CI لتعديلات الحارس التلقائي والتقاط Android: التحليل بلا مشكلات، و**184 اختبارًا** ناجحًا، وAPK بحجم **63.3 MB**، واختبارات الالتقاط الأصلية، وفحص أذونات APK المبني. يخص ذلك الشيفرة `5f00646930609e82e3c044cd2bcc5cdfcc5dd84d` في [التشغيل 37723093465](https://github.com/abbady110/spider-aim-/actions/runs/37723093465)، المكتمل في **2026-10-08 الساعة 03:37:32 UTC**. هذه النتائج لا تثبت دقة التعرف على أجهزة فعلية أو تحسن اللعب.

## Verified automatic-recognition baseline before the floating panel

| Check | Current status |
| --- | --- |
| `python3 scripts/check_source.py` | PASS — 218 offline structural checks; no Flutter/native compilation |
| `git diff --check` | PASS — whitespace validation only |
| `bash -n scripts/bootstrap_flutter.sh scripts/verify.sh scripts/check_apk_permissions.sh` | PASS — shell syntax validation only |
| `flutter pub get` | PASS — current revision GitHub Actions |
| `flutter analyze --fatal-infos` | PASS — no issues, 12.8 seconds |
| `flutter test --coverage` | PASS — 184 tests, 10 seconds |
| `./gradlew :app:testReleaseUnitTest` | PASS — native capture safety task; `BUILD SUCCESSFUL in 41s` |
| Android APK compilation and upload | PASS — release ARM/ARM64 APK, 63.3 MB |
| Built APK network permission audit | PASS — `aapt` confirmed no `INTERNET` or `ACCESS_NETWORK_STATE` permission |
| MediaProjection / Usage Access consent on physical Android | NOT RUN |
| Real PUBG HUD/locale/device recognition validation | NOT RUN |
| Measured capture CPU/battery/FPS overhead | NOT RUN |
| iOS cross-app capture | NOT IMPLEMENTED; requires ReplayKit Broadcast Upload Extension and provisioning |

Tested source revision: [`5f00646930609e82e3c044cd2bcc5cdfcc5dd84d`](https://github.com/abbady110/spider-aim-/commit/5f00646930609e82e3c044cd2bcc5cdfcc5dd84d). The completed workflow and downloaded logs/artifact metadata were checked independently; the subsequent documentation update does not change that tested code revision.

- [Current APK artifact: spider-aim-android-apk](https://github.com/abbady110/spider-aim-/actions/runs/37723093465/artifacts/11526707072): `app-release.apk`, 63.3 MB as reported by Flutter; compressed artifact **29,904,678 bytes**. Expires **2026-11-07 03:37:24 UTC**.
- [Current verification artifact: spider-aim-verification](https://github.com/abbady110/spider-aim-/actions/runs/37723093465/artifacts/11526856659): analysis, Flutter test, APK build, native capture test, and permission-audit logs; compressed artifact **10,975 bytes**. Expires **2026-11-07 03:37:26 UTC**.

Verified current job output:

```text
No issues found! (ran in 12.8s)
00:10 +184: All tests passed!
Built build/app/outputs/flutter-apk/app-release.apk (63.3MB)
BUILD SUCCESSFUL in 41s
```

The final line belongs to `./gradlew :app:testReleaseUnitTest`. The separate actual-APK `aapt` audit passed and found neither network permission. No coverage percentage or physical-device performance result is asserted.

Current source implements six automatic modes: `TRAINING_SAFE`, `WAREHOUSE_SAFE`, `ARENA_SAFE`, `SAFE_UNRANKED`, `COMPETITIVE_BLOCKED`, and `UNKNOWN_BLOCKED`. The Android path uses consented MediaProjection, a media-projection foreground service, UsageStats foreground checks, and bundled local Latin OCR. Manual selections cannot authorize any operation. Synthetic automated fixtures exercise confidence, independent frames, temporal checks, competitive latching, revocation, and transaction gates; they do not establish accuracy on real screenshots.

The source checker validates only repository structure and selected invariants, including the explicit official capture-permission/service allowlist. Its result is not Dart/Flutter compilation, a native API test, or proof that the merged APK manifest has no additional library declarations.

The source manifest explicitly removes `INTERNET` and `ACCESS_NETWORK_STATE` permissions from transitive dependencies. CI also inspects permissions in the built APK using `aapt` and refuses artifact upload if either network permission survives manifest merging. The OCR model is bundled and needs no network connection.

## Historical baseline: 2026-10-07 GitHub delivery and verified CI

- The original 60-file local source tree was uploaded in commit `14a8b78`; its contents were preserved.
- The [first workflow run](https://github.com/abbady110/spider-aim-/actions/runs/37621600023) failed during Android SDK setup because its default requested tools package was retired.
- Commit `be56b11687757ce70257ad8941460efc99113f41` explicitly requests `platform-tools`. Android SDK setup, Flutter setup, dependency resolution, static analysis, unit/widget tests, APK compilation, and artifact upload all passed in [run 37621731959](https://github.com/abbady110/spider-aim-/actions/runs/37621731959), completed at **2026-10-07 12:38:22 UTC**.
- [APK artifact: spider-aim-android-apk](https://github.com/abbady110/spider-aim-/actions/runs/37621731959/artifacts/11482581407): contains `app-release.apk` (31.4 MB reported by Flutter); compressed artifact size **15,219,432 bytes**. Expires **2026-11-06 12:38:05 UTC**.
- [Verification artifact: spider-aim-verification](https://github.com/abbady110/spider-aim-/actions/runs/37621731959/artifacts/11482581411): build/analysis/test logs and coverage output. No coverage percentage or real-device performance result is asserted in this report.

Exact output from that historical revision:

```text
No issues found! (ran in 12.1s)
00:07 +111: All tests passed!
Built build/app/outputs/flutter-apk/app-release.apk (31.4MB)
```

## Historical local checks for the previous revision

| Check | Result | Scope |
| --- | --- | --- |
| `bash -n scripts/bootstrap_flutter.sh scripts/verify.sh` | PASS | Shell syntax only; does not execute Flutter or generate native tooling |
| `git diff --check` | PASS | Whitespace/conflict-marker checking; does not compile Dart, Kotlin, or Swift |
| `python3 scripts/check_source.py` | PASS: 107 offline structural checks | Local import targets, XML/plist parsing, actual SQLite DDL/immutable-backup triggers, mobile platform/manifest and CI checks; not a Dart compiler or Flutter test runner |
| Source/documentation review | Completed | Reviewed guard boundaries, manual workflow, source modules, CI steps, and documented unavailable capabilities |

## Historical Flutter/Android results for the previous revision

| Check | Status |
| --- | --- |
| `flutter pub get` | PASS — GitHub Actions |
| `flutter analyze` | PASS — GitHub Actions; `flutter analyze --fatal-infos` |
| `flutter test` | PASS — 111 unit/widget tests in GitHub Actions |
| `flutter build apk` | PASS — release APK, ARM/ARM64, 31.4 MB |
| iOS compilation/signing | NOT RUN — requires macOS, Xcode, and provisioning |
| Physical Android/iPhone/iPad testing | NOT RUN |
| GitHub Actions execution and APK upload | PASS — successful run and downloadable artifacts linked above |

During the original local-only delivery, the environment could not download the missing build tooling; local Flutter commands exited 127 (`flutter: command not found`), and a GitHub write returned **`403 Resource not accessible by integration`**. That GitHub permission blocker has since been resolved and the source has been pushed successfully. Those historical local limitations do not describe the successful GitHub Actions environment. The CI results above establish analysis, automated tests, and APK compilation; they do not establish physical-device behavior or gameplay improvement.

Structural checks for the current revision can be repeated without Flutter using `python3 scripts/check_source.py`. The historical count above describes the earlier checker; new source/imports/permission checks change that count. Success does not substitute for static analysis, unit/widget test execution, or APK compilation.

Direct package versions are pinned in `pubspec.yaml`. CI dependency resolution passed, but the generated `pubspec.lock` has not been retrieved or committed. Capturing that lockfile remains a reproducibility improvement for transitive dependencies.

## Current test coverage validated by CI

| File | Behavioral coverage in this revision |
| --- | --- |
| `test/guard_test.dart` | Automatic-only permission; no manual override from unknown/competition; trusted frames, freshness, capture revocation |
| `test/mode_recognition_test.dart` | Multi-frame evidence, heuristic threshold, contradictions, temporal validity, pixel-fingerprint independence, competitive session latch |
| `test/policy_test.dart` | NON_GYRO, forbidden settings, per-context keys, multi-metric acceptance, battery policy |
| `test/workflow_test.dart` | Trial consent, backup/testing/approval/restore, high-confidence capture preconditions, capture revocation before final approval and inside transactions |
| `test/storage_test.dart` | SQLite persistence/migration, immutable backup protection, transaction rollback, restart recovery, device isolation |
| `test/device_test.dart` | Official-device report parsing, unknown values, unsupported platforms/emulators, fail-closed native errors |
| `test/engines_test.dart` | Aim evidence, confounders, hit/death uncertainty, movement, throwables, battery calculations, landing geometry |
| `test/widget_test.dart` | Arabic RTL, phone/tablet navigation, automatic status, manual-choice no-override, locked forms and final approval |
| `android/app/src/test/kotlin/org/spideraim/coach/capture/PubgCueExtractorTest.kt` | Native OCR/HUD cue extraction, independent evidence, misleading labels, and fail-closed unsupported inputs |

## Reproduce automated validation

With Flutter **3.35.7 stable**, Java **17**, and Android SDK installed:

```bash
bash scripts/verify.sh
```

The bootstrap step generates missing standard Gradle wrapper files and iOS Xcode project/assets from that Flutter SDK. It preserves existing custom native sources and configuration. This bootstrap step ran successfully in CI; generated tooling does not imply an iOS build or signing result.

After the command succeeds, the expected local APK path is:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The [Android APK workflow](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml) performs dependency resolution, analysis, Flutter tests, APK compilation, native capture safety tests, and a permission audit of the built APK before artifact upload. Native tests use `./gradlew :app:testReleaseUnitTest`, with `native-capture-tests.log` in the verification artifact. `aapt` must find neither `INTERNET` nor `ACCESS_NETWORK_STATE` in the actual APK. Download the current APK linked in the first section while signed in, extract `app-release.apk`, and install on a supported physical Android device. Development signing is used; production updates require a stable private release key.

## Physical-device acceptance still required

Validate installation on an ARM Android phone and tablet, screen-capture consent denial/revocation, Usage Access denial/revocation, the visible capture stop action, foreground changes, rotation, process interruption, stale frames, and severe-heat shutdown. Exercise actual Training, Warehouse, Arena, unknown menus, Ranked, and Battle Royale flight/descent screens across game locales and custom HUD layouts. Unsupported Arabic/layouts must remain blocked. Establish false-unlock and false-block rates from real footage before claiming recognition accuracy; a 0.95 heuristic threshold is not proof of 95% measured correctness.

Also validate official device readings, durable approved/trial/backup retention, manual apply/restore instructions, and Arabic layout with large text. Measure SPIDER AIM's capture CPU/battery overhead and reliable game-FPS impact. Confirm stability and observed-hit improvements with repeated player trials. Automated tests cannot establish those gameplay outcomes or confirm server hit registration.

Returning to the main SPIDER AIM activity still closes its forms. The new optional Android panel uses the existing guarded workflow while PUBG remains foreground; native window/keyboard/secure-capture behavior still requires physical-device testing. See [Overlay](OVERLAY.md).

نجحت نتائج CI الحالية للتحليل و184 اختبارًا وبناء APK واختبارات الالتقاط الأصلية وفحص أذونات APK. قسم 111 اختبارًا محفوظ كسجل للنسخة السابقة فقط. ما زالت تجارب الأجهزة وواجهات PUBG الفعلية مطلوبة، ولا يوجد حاليًا التقاط PUBG عبر التطبيقات على iOS. لا تثبت اختبارات الوحدة تحسن ثبات التصويب أو Hit Registration أثناء اللعب، ويبقى قيد التفاعل عند الرجوع إلى SPIDER AIM قائمًا.
