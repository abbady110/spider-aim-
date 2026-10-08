# Verification status / حالة التحقق

Current source review date: **2026-10-08 (UTC)**.

## Current verified floating-panel revision: 1.0.1+2

The authorized Android floating panel and its existing guarded settings workflow passed analysis, Flutter tests, native tests, APK compilation, and the built-APK permission audit. The workflow and final logs/artifact metadata were independently checked for source revision [`f4fdde7728e573258b308824b57893fb47278d7e`](https://github.com/abbady110/spider-aim-/commit/f4fdde7728e573258b308824b57893fb47278d7e) in [run 37736827044](https://github.com/abbady110/spider-aim-/actions/runs/37736827044), job `113178157208`, completed **2026-10-08 at 06:23:05 UTC**. A subsequent documentation-only update does not change that tested code revision.

نجح CI للإصدار **1.0.1+2** المتضمن لوحة Android العائمة: التحليل بلا مشكلات، و**214 اختبارًا** ناجحًا، وAPK بحجم **63.5 MB**، ومهمة الاختبارات الأصلية، وفحص أذونات APK المبني. هذه النتائج لا تثبت سلوك اللوحة أو لوحة المفاتيح أو الالتقاط الآمن على أجهزة فعلية، ولا تثبت دقة التعرف أو تحسن اللعب.

| Check | Current status |
| --- | --- |
| `python3 scripts/check_source.py` | PASS — 247 offline structural checks; no Flutter/native compilation |
| `git diff --check` | PASS — whitespace validation only |
| `bash -n scripts/bootstrap_flutter.sh scripts/verify.sh scripts/check_apk_permissions.sh` | PASS — shell syntax validation only |
| `flutter pub get` | PASS — current revision GitHub Actions |
| `flutter analyze --fatal-infos` | PASS — no issues, 9.8 seconds |
| `flutter test --coverage` | PASS — 214 tests, 10 seconds |
| `./gradlew :app:testReleaseUnitTest` | PASS — native test task; `BUILD SUCCESSFUL in 31s` |
| Android APK compilation and upload | PASS — release ARM/ARM64 APK, 63.5 MB |
| Built APK permission audit | PASS — `aapt` lists `SYSTEM_ALERT_WINDOW`; neither `INTERNET` nor `ACCESS_NETWORK_STATE` is present |
| MediaProjection / Usage Access / overlay consent on physical Android | NOT RUN |
| Physical-device floating panel, keyboard, rotation, and secure capture | NOT RUN |
| Real PUBG HUD/locale/device recognition validation | NOT RUN |
| Measured capture/panel CPU/battery/FPS overhead | NOT RUN |
| iOS compilation/signing | NOT RUN — requires macOS, Xcode, and provisioning |
| iOS cross-app capture / floating panel | NOT IMPLEMENTED; Android overlay is not an iOS implementation |

- [Current APK artifact: spider-aim-android-apk](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532685466): `app-release.apk`, 63.5 MB as reported by Flutter; compressed artifact **29,996,977 bytes**. Expires **2026-11-07 06:22:59 UTC**.
- [Current verification artifact: spider-aim-verification](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532725356): analysis, Flutter test, APK build, native test, and permission-audit logs; compressed artifact **13,198 bytes**. Expires **2026-11-07 06:23:02 UTC**.

Verified current job output:

```text
No issues found! (ran in 9.8s)
00:10 +214: All tests passed!
Built build/app/outputs/flutter-apk/app-release.apk (63.5MB)
BUILD SUCCESSFUL in 31s
PASS: built APK has no INTERNET or ACCESS_NETWORK_STATE permission.
```

The Gradle success line belongs to `./gradlew :app:testReleaseUnitTest`. Its log establishes task success, not an explicit executed native test count; no count is inferred from test source files. The actual `aapt` output lists `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `POST_NOTIFICATIONS`, `SYSTEM_ALERT_WINDOW`, `PACKAGE_USAGE_STATS`, and the app's own receiver permission, with neither network permission. The separate overlay special-access grant is still required on the device. No coverage percentage or physical-device performance result is asserted.

## Historical automatic-recognition baseline before the floating panel

Revision `5f00646930609e82e3c044cd2bcc5cdfcc5dd84d` passed [run 37723093465](https://github.com/abbady110/spider-aim-/actions/runs/37723093465), completed **2026-10-08 at 03:37:32 UTC**. These 184-test results predate the floating panel and are retained as historical evidence only.

| Check | Historical baseline status |
| --- | --- |
| `python3 scripts/check_source.py` | PASS — 218 offline structural checks; no Flutter/native compilation |
| `git diff --check` | PASS — whitespace validation only |
| `bash -n scripts/bootstrap_flutter.sh scripts/verify.sh scripts/check_apk_permissions.sh` | PASS — shell syntax validation only |
| `flutter pub get` | PASS — historical baseline GitHub Actions |
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

- [Historical APK artifact: spider-aim-android-apk](https://github.com/abbady110/spider-aim-/actions/runs/37723093465/artifacts/11526707072): `app-release.apk`, 63.3 MB as reported by Flutter; compressed artifact **29,904,678 bytes**. Expires **2026-11-07 03:37:24 UTC**.
- [Historical verification artifact: spider-aim-verification](https://github.com/abbady110/spider-aim-/actions/runs/37723093465/artifacts/11526856659): analysis, Flutter test, APK build, native capture test, and permission-audit logs; compressed artifact **10,975 bytes**. Expires **2026-11-07 03:37:26 UTC**.

Verified historical baseline job output:

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
| `test/overlay_test.dart` | Guarded bridge dispatch, session-bound expiring single-use forms, explicit baseline/test consent, evidence-bound proposals, trial-only approval, final comparison/approval, stale or revoked capture rejection |
| `test/widget_test.dart` | Arabic RTL, phone/tablet navigation, automatic status, manual-choice no-override, locked forms and final approval |
| `android/app/src/test/kotlin/org/spideraim/coach/capture/PubgCueExtractorTest.kt` | Native OCR/HUD cue extraction, independent evidence, misleading labels, and fail-closed unsupported inputs |
| `android/app/src/test/kotlin/org/spideraim/coach/overlay/OverlayAuthorizationPolicyTest.kt` | Native panel authorization policy, independent capture evidence, session/foreground/freshness checks, Dart heartbeat, and competitive latching |

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

The [Android APK workflow](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml) performs dependency resolution, analysis, Flutter tests, APK compilation, native safety tests, and a permission audit of the built APK before artifact upload. Native tests use `./gradlew :app:testReleaseUnitTest`, with `native-capture-tests.log` in the verification artifact. `aapt` must find neither `INTERNET` nor `ACCESS_NETWORK_STATE` in the actual APK; the verified output also lists the panel's `SYSTEM_ALERT_WINDOW` permission. Download the current APK linked in the first section while signed in and extract `app-release.apk`. Test on a supported physical Android device without existing SPIDER AIM data; these two delivered artifacts have incompatible signatures as documented below.

## Confirmed installation compatibility limitation

The public signer certificates were extracted read-only from the APK v2 signing blocks in the downloaded previous and current artifacts and inspected with OpenSSL. Both certificate subjects are `CN=Android Debug`, but their SHA-256 fingerprints differ:

| Artifact | Public signing-certificate SHA-256 |
| --- | --- |
| Previous `11526707072`, run `37723093465` | `BD:4E:C7:BB:8A:66:DC:5A:83:E2:74:DC:E0:54:43:01:5A:4C:A6:2F:A8:A2:79:ED:8A:68:C9:16:BD:F2:F9:75` |
| Current `11532685466`, run `37736827044` | `0B:60:89:DD:CC:80:77:06:AF:FC:1F:7F:3C:88:BE:1D:31:C5:F2:38:56:51:70:C8:CF:FB:73:5A:4A:54:FA:F4` |

Android cannot install the current APK over that previous APK as an in-place update. No APK was modified, no private signing key was accessed, and no physical-device installation is asserted by this comparison. Preserve the installed app if settings, samples, versions, or backups exist or their presence is uncertain. Those backups are local app data, not an external export, and the previous version has no data-export feature; uninstall may erase them.

Future consistent builds require a stable private release signing key retained securely by the owner. A newly created key cannot repair compatibility with the existing differently signed installation; an in-place update needs its original signer. No private keys or passwords belong in the repository.

تأكد اختلاف توقيع APK السابق والحالي؛ لا يمكن تثبيت الحالي كتحديث فوق السابق. لا تحذف التطبيق عند وجود بيانات أو الشك في وجودها. نسخ Backup الداخلية ليست تصديرًا خارج التطبيق، ولم تُنفذ تجربة تثبيت فعلية على هاتف المستخدم.

## Physical-device acceptance still required

Validate installation on an ARM Android phone and tablet, screen-capture consent denial/revocation, Usage Access denial/revocation, the visible capture stop action, foreground changes, rotation, process interruption, stale frames, and severe-heat shutdown. Exercise actual Training, Warehouse, Arena, unknown menus, Ranked, and Battle Royale flight/descent screens across game locales and custom HUD layouts. Unsupported Arabic/layouts must remain blocked. Establish false-unlock and false-block rates from real footage before claiming recognition accuracy; a 0.95 heuristic threshold is not proof of 95% measured correctness.

Also validate official device readings, durable approved/trial/backup retention, manual apply/restore instructions, and Arabic layout with large text. Measure SPIDER AIM's capture CPU/battery overhead and reliable game-FPS impact. Confirm stability and observed-hit improvements with repeated player trials. Automated tests cannot establish those gameplay outcomes or confirm server hit registration.

Returning to the main SPIDER AIM activity still closes its forms. The new optional Android panel uses the existing guarded workflow while PUBG remains foreground; native window/keyboard/secure-capture behavior still requires physical-device testing. See [Overlay](OVERLAY.md).

نجحت نتائج CI الحالية للتحليل و214 اختبارًا وبناء APK ومهمة الاختبارات الأصلية وفحص أذونات APK. قسما 184 و111 اختبارًا محفوظان كسجل للنسختين السابقتين فقط. ما زالت تجارب اللوحة ولوحة المفاتيح والالتقاط الآمن على الأجهزة وواجهات PUBG الفعلية مطلوبة، ولا يوجد حاليًا التقاط PUBG عبر التطبيقات على iOS. لا تثبت اختبارات الوحدة تحسن ثبات التصويب أو Hit Registration أثناء اللعب، ويبقى قيد التفاعل عند الرجوع إلى واجهة SPIDER AIM الرئيسية قائمًا.
