# SPIDER AIM

مدرّب محلي لمعايرة التصويب والتحكم باللمس في PUBG باستخدام Flutter، مخصص لهواتف وأجهزة Android اللوحية وiPhone وiPad. الملف الافتراضي **NON_GYRO / TOUCH_ONLY**، والجيروسكوب وجيروسكوب ADS معطّلان دائمًا داخل ملفات التطبيق.

الأولوية لثبات التصويب ونتائج الإصابات المقاسة، مع فصل أخطاء التحكم عن الشبكة والأداء والحرارة. قياسات التصويب والتحكم يدخلها اللاعب؛ أضيف التعرف التلقائي على وضع اللعب من الشاشة على Android بواسطة OCR محلي وقواعد تحفظية. لا توجد قراءة مباشرة لبيانات PUBG أو تأكيد من خوادمها للإصابات.

**حالة التحقق:** الإصدار السابق بتاريخ 2026-10-07 اجتاز التحليل و**111 اختبارًا** وبنى APK بحجم **31.4 MB** في [التشغيل التاريخي](https://github.com/abbady110/spider-aim-/actions/runs/37621731959). هذه النتائج لا تتحقق من تعديلات التعرف التلقائي الحالية؛ تشغيل CI الجديد قيد التحقق. اختبار الالتقاط وواجهات PUBG على أجهزة فعلية وقياس التحسن أثناء اللعب ما زال مطلوبًا. راجع [سجل التحقق](docs/VERIFICATION.md) قبل تنزيل أي إصدار.

## الميزات المنفذة

- واجهة عربية RTL داكنة ومتجاوبة، وملف مستقل لكل جهاز.
- حارس تلقائي يفحص أدلة الشاشة على Android بعد موافقة التقاط النظام وإذن Usage Access؛ اختيار اسم الوضع يدويًا لا يفتح أي صلاحية.
- اكتشاف معلومات الجهاز والشاشة والبطارية والحالة الحرارية عبر APIs عامة متاحة. القيم غير المتاحة تبقى `UNKNOWN`، خصوصًا معدل أخذ عينات اللمس وFPS الخاص بلعبة أخرى.
- ملفات معايرة مستقلة حسب السلاح والسكوب والملحقات والمسافة، وقياسات يدوية موثقة المصدر، وتحليل أنماط متعددة العينات.
- اقتراحات تشرح المشكلة والسبب والدليل وعدد العينات والقيمة الحالية والمقترحة والأثر المتوقع والمقايضة.
- دورة موافقة على التجربة، وBackup كامل لبيانات الإعدادات المسجلة، ونسخة تجريبية، ومقارنة، ثم موافقة نهائية منفصلة.
- تخزين SQLite محلي مع إصدارات مخطط قاعدة البيانات، وسجل الإصدارات والنسخ الاحتياطية ونتائج الاختبارات، واستعادة بيانات النسخة السابقة.
- تشخيص إرشادي للإصابات والوفيات، ومعايرة الحركة والقنابل، وتقارير بطارية، وحسابات هبوط مبنية على مدخلات اللاعب.
- GitHub Actions للتحليل والاختبارات وبناء Android APK ورفع APK وسجل التحقق كـArtifacts؛ يجب مراجعة نتيجة التشغيل الخاصة بالتعديل الحالي.

## التعرف التلقائي وقفل الوضع

على Android يبدأ الالتقاط فقط بعد موافقة `MediaProjection` الرسمية، مع طلب إذن الإشعارات عند الحاجة في Android 13 فأحدث. يعمل في خدمة أمامية ظاهرة بإشعار إيقاف، ويستخدم `UsageStatsManager` بعد منح **Usage Access** من إعدادات النظام للتحقق أن PUBG في المقدمة. في Android 14 يطلب مسار النظام مشاركة الشاشة كاملة لتجنب تحليل نافذة مختلفة اختارها المستخدم. منح الإذن وحده لا يثبت الوضع الآمن.

يحلل ML Kit المضمّن نصوصًا لاتينية محليًا من صور منخفضة الدقة، بحد أقصى 960 بكسل للضلع الأطول، وبفاصل لا يقل عن ثانيتين، مع مهمة OCR واحدة في الوقت نفسه. يلزم أربعة إطارات ذات بصمات بكسل مختلفة خلال ست ثوانٍ على الأقل، وأدلة مستقلة للوضع، ودرجة ثقة لا تقل عن 0.95. تنتهي صلاحية الدليل بعد 12 ثانية. هذه الدرجة معيار تحفظي وليست احتمال دقة مثبتًا تجريبيًا.

| الحالة | السلوك |
| --- | --- |
| `TRAINING_SAFE` | تدريب ثبتت مؤشراته تلقائيًا |
| `WAREHOUSE_SAFE` | Warehouse ثبتت مؤشراته تلقائيًا |
| `ARENA_SAFE` | Arena/TDM ثبتت مؤشراته تلقائيًا |
| `SAFE_UNRANKED` | تسمية Unranked صريحة مع مؤشرات آمنة مستقلة |
| `COMPETITIVE_BLOCKED` | قفل المنافسة وBattle Royale |
| `UNKNOWN_BLOCKED` | لا دليل حديث كافٍ؛ جميع عمليات المعايرة مقفولة |

مؤشر مصنف أو Battle Royale بدرجة 0.80 أو أكثر، مثل الطائرة أو مسار الطيران أو النزول أو المظلة، يقفل الجلسة فورًا ويوقف معالجة البكسل وOCR مع إبقاء الخدمة وإشعار الإيقاف حتى إنهاء الجلسة. التعارض، الدليل القديم، غياب PUBG في المقدمة، أو فقد إذن الالتقاط يعيد القفل. الأزرار اليدوية للسجل عرض تاريخي فقط؛ لا تتجاوز الحارس.

**قيد الاستخدام الحالي:** الرجوع من PUBG إلى SPIDER AIM يغلق حارس النماذج لحماية شرط التطبيق الموجود في المقدمة. لذلك لم تُحل بعد تجربة كتابة الإعدادات التفاعلية داخل SPIDER AIM بينما PUBG في المقدمة. يلزم مستقبلًا تصميم واجهة مصرح بها أو مراجعة جلسة موثقة؛ لا يوجد تجاوز يدوي لهذا القيد.

التعرف الحالي تحفظي ولم يُعتمد بعد على مصفوفة حقيقية من الأجهزة وتخطيطات HUD ولغات PUBG. العربية والتخطيطات غير المدعومة تبقى `UNKNOWN_BLOCKED`. التعرف على الوضع لا يعني تحليل Aim أو وفاة آليًا من الفيديو.

## حدود مهمة

لا توفر PUBG هنا API عامة لقراءة إعداداتها أو تعديلها أو تأكيد وضع المباراة من الخادم. التعرف الحالي يستدل من الشاشة ضمن الحدود التالية:

1. **التطبيق اليدوي إلزامي:** يعرض SPIDER AIM القيم، ويغيّر اللاعب إعدادات PUBG بنفسه عبر واجهتها الرسمية. Backup يحفظ الإعدادات التي سجلها اللاعب في SPIDER AIM، وليس ملفات PUBG غير القابلة للقراءة. يجب إدخال إعدادات البداية كاملة ودقيقة.
2. **الاسترجاع داخل SPIDER AIM فوري؛ داخل PUBG يدوي:** يسترجع التطبيق سجل الإعدادات ويعرض القيم التي يجب إعادة تطبيقها في اللعبة. لا يدّعي إعادة ضبط اللعبة تلقائيًا.
3. **المنافسة وUNKNOWN مغلقان:** لا توجد صلاحية معايرة من تصريح المستخدم. مسار Android المصرح يجمع مؤشرات الوضع فقط، ويمنع الحارس المعايرة والتجارب والتعديلات ومساعد الهبوط عند القفل. التصنيف المرئي ليس تأكيدًا رسميًا من PUBG.
4. لا يوجد ضمان لتحسن Hit Registration؛ لا يستطيع التطبيق إجبار الخادم على تسجيل إصابة، أو معرفة السبب الحقيقي للـDesync من بيانات غير متاحة. النتيجة غير المدعومة بدليل هي `INCONCLUSIVE`.
5. لا يعدّل التطبيق سرعة اللاعب أو الضرر أو ملفات اللعبة أو الشبكة، ولا يتحكم بالتصويب والحركة والرمي والمظلة. لا يستخدم Accessibility أو Root أو Jailbreak أو APIs خاصة.
6. لا يُخفض FPS أو جودة الرسومات أو معدل تحديث اللعبة تلقائيًا. تخفيف الحمل يخص عمل SPIDER AIM نفسه.
7. لا يوجد دعم لسطح المكتب أو الويب أو المحاكيات. اختبارات الوحدة والواجهة تعمل على بيئة CI، ولا تعني دعم المحاكيات كمنصة تشغيل.
8. Android هو مسار البناء والتحقق الأول. لا يوجد حاليًا التقاط شاشة PUBG عابر للتطبيقات على iOS؛ يلزم تنفيذ ReplayKit Broadcast Upload Extension وتوفير توقيع وصلاحيات Apple. يظل الحارس هناك مغلقًا بدل الادعاء أن كشف الوضع منفذ. بناء وتوقيع iOS يتطلبان macOS وXcode وتجربة أجهزة فعلية.
9. إشعارات الاقتراحات محفوظة داخل واجهة SPIDER AIM وليست Push. إشعار Android الخاص بخدمة الالتقاط نشط فقط أثناء خدمة MediaProjection ويتيح إيقافها. الالتقاط منخفض المعدل ويتوقف عند حرارة شديدة؛ لا يوجد تسجيل فيديو مستمر أو تحليل Aim خلفي مكتمل.
10. تقرير البطارية يعتمد على قراءات البداية والنهاية؛ لا يرصد بالضرورة الأحداث الحرارية أو الشحن بين القراءتين. مساعد الهبوط مراجعة هندسية تدريبية من مدخلاتك، ولا يصدر أمر قفز حيًا أو يختار نقطة هبوط من خريطة غير متاحة.

راجع [حدود القدرات ومصادر البيانات](docs/LIMITATIONS.md) و[قواعد السلامة](docs/SAFETY.md).

## دورة الاستخدام

1. افتح ملف جهازك. على Android، امنح Usage Access إن أردت التحقق التلقائي، ثم ابدأ الالتقاط ووافق عبر نافذة النظام. يمكنك إيقافه من إشعار الخدمة.
2. انتظر تعرفًا آمنًا من شاشة PUBG. اختيار Training أو Warehouse أو Unranked يدويًا ليس موافقة تشغيل. عند السماح، سجّل إعدادات البداية الحقيقية بدقة؛ لا تُنسخ حساسية الهاتف إلى الجهاز اللوحي.
3. اجمع عدة محاولات متقاربة الظروف لنفس السلاح والسكوب والملحقات والمسافة. أدخل النتائج الحقيقية، ولا تعامل القياسات اليدوية على أنها telemetry آلية.
4. راجع الاقتراح، ثم اختر موافقة على التجربة أو رفض أو تأجيل. عند الموافقة يحفظ التطبيق Backup قبل إنشاء النسخة التجريبية.
5. طبّق القيم بنفسك داخل PUBG، واختبرها في وضع غير مصنف. سجّل النتائج المقارنة. لا يصبح TESTING معتمدًا تلقائيًا.
6. اعتمد بعد اجتياز المقارنة وموافقتك النهائية، أو أعد الاختبار أو ارفض أو استرجع النسخة السابقة يدويًا داخل PUBG.

## البناء

المتطلبات: Flutter **3.35.7 stable**، Java **17**، وAndroid SDK. البناء محصور في ARM/ARM64، للهواتف والأجهزة اللوحية الفعلية.

استخدم مجلد المشروع المحلي، أو نزّل الشيفرة المرفوعة إلى GitHub:

```bash
git clone https://github.com/abbady110/spider-aim-.git
cd spider-aim-
bash scripts/bootstrap_flutter.sh
flutter pub get
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --release --target-platform android-arm,android-arm64
```

أو نفّذ `bash scripts/verify.sh`. يوجد APK بعد نجاح البناء في:

```text
build/app/outputs/flutter-apk/app-release.apk
```

ينشئ سكربت bootstrap أدوات Gradle الثنائية ومشروع Xcode وموارده المفقودة من نسخة Flutter المثبتة داخل مجلد مؤقت، وينسخ الملفات المفقودة فقط. لا يستبدل شيفرة Android أو iOS أو Dart الموجودة.

APK المبني مخصص للتجربة والتثبيت الجانبي وفق إعداد توقيع التطوير الحالي؛ تحتاج الإصدارات الموزعة والتحديثات المتوافقة إلى مفتاح توقيع إصدار ثابت يحتفظ به المالك. لا تُضف مفاتيح أو كلمات مرور إلى المستودع.

## تنزيل APK من GitHub Actions

افتح [Actions → Android APK](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml)، ثم أحدث تشغيل ناجح. من **Artifacts** نزّل `spider-aim-android-apk`، وفك ZIP للوصول إلى `app-release.apk`. يحتوي `spider-aim-verification` على سجلات التحليل والاختبارات والبناء والتغطية عند توفرها. يلزم تسجيل الدخول إلى GitHub لتنزيل Artifacts، ومدة الاحتفاظ 30 يومًا.

نتائج البناء المؤكد بتاريخ 2026-10-07 **للنسخة السابقة فقط**: [APK](https://github.com/abbady110/spider-aim-/actions/runs/37621731959/artifacts/11482581407) و[سجلات التحقق](https://github.com/abbady110/spider-aim-/actions/runs/37621731959/artifacts/11482581411). ينتهي الاحتفاظ بهذه الملفات في 2026-11-06؛ أعد تشغيل Workflow لإنشاء ملفات جديدة بعد ذلك.

ينفّذ Workflow: Checkout → Java/Android/Flutter setup → `flutter pub get` → `flutter analyze` → `flutter test` → APK build → `:app:testReleaseUnitTest` لاختبارات الالتقاط الأصلية → artifact upload. وجود ملف Workflow وحده ليس إثبات نجاح البناء؛ راجع نتيجة التشغيل الفعلية وسجلاته، ومنها `native-capture-tests.log`.

## البنية والخصوصية

طبقات مستقلة لمحركات القياس والتشخيص، وحارس الوضع، وإدارة ملفات الجهاز والإصدارات، وتخزين SQLite، وواجهات الجهاز الأصلية، وواجهة Flutter. انظر [Architecture](docs/ARCHITECTURE.md).

تُحفظ بيانات الجلسات والملفات محليًا. صور الالتقاط ونصوص OCR الخام مؤقتة في الذاكرة؛ لا تُحفظ ولا تُرسل عبر الشبكة. تنتقل مؤشرات دلالية مقتضبة إلى الحارس، وتُحرر الصور بعد المعالجة. نموذج ML Kit اللاتيني مضمّن، ولا يوجد رفع فيديو أو تحليل سحابي. لا تحفظ معرفات حساسة مثل IMEI. البيانات المحلية غير مشفرة على مستوى قاعدة البيانات؛ تعتمد حمايتها على sandbox وتشفير نظام التشغيل.

مراجع APIs الرسمية: [MediaProjection](https://developer.android.com/media/grow/media-projection)، [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)، [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).

---

## English

SPIDER AIM is a local Flutter aim-and-control calibration coach for physical Android phones/tablets and iPhone/iPad. The default policy is `NON_GYRO`, `TOUCH_ONLY`, gyroscope disabled, and ADS gyroscope disabled. Android is the first intended build-validation target.

**Verification status:** the previous 2026-10-07 revision passed analysis and **111 tests** and built a **31.4 MB APK** in this [historical run](https://github.com/abbady110/spider-aim-/actions/runs/37621731959). That result does not validate the current automatic-recognition changes; the new CI result is pending. Real-device capture, PUBG HUD/layout validation, and measured gameplay improvement remain outstanding. See [Verification](docs/VERIFICATION.md).

The source implements an Arabic RTL dark interface, per-device profiles, official-API device/battery/thermal observations, weapon/scope/attachment/distance calibration contexts, evidence-based recommendations, movement/throwables review, death and hit-registration differential diagnostics, battery reports, and a local SQLite-backed settings-version workflow.

Coaching metrics still use structured player-entered evidence. Android now has an authorized screen-based mode-recognition pipeline: official MediaProjection consent, a visible media-projection foreground service, Usage Access granted in Android settings to verify the foreground PUBG package, and bundled on-device Latin ML Kit OCR. Frames have a 960-pixel maximum long edge and a minimum two-second sampling interval; only one OCR task runs at a time. No raw screen pixels or OCR text are persisted or sent over the network.

The guard requires at least four distinct pixel fingerprints across six seconds, consistent independent safe indicators, and a heuristic score of at least 0.95. Evidence expires after 12 seconds. The six states are `TRAINING_SAFE`, `WAREHOUSE_SAFE`, `ARENA_SAFE`, `SAFE_UNRANKED`, `COMPETITIVE_BLOCKED`, and `UNKNOWN_BLOCKED`. A credible Ranked/Battle Royale cue at 0.80 or above immediately latches the competitive lock and shuts down pixel/OCR work while retaining the service/session stop notification. Ambiguity, missing consent, unverified foreground, old or frozen frames block access. Manual historical selections are read-only and cannot authorize operations. Android 14 uses full-display capture consent to avoid analyzing an unrelated selected app window; notification permission is requested where Android requires it.

The confidence score is not an empirically established probability. Current Latin OCR/HUD rules still need real-device, locale, and layout validation. Unsupported Arabic game UI or HUD layouts remain unknown. Screen mode recognition does not implement automatic aim/video/death measurement or establish server-confirmed game telemetry.

Proposal notices remain in-app; the separate Android foreground-service notification provides a capture stop action. Low-rate mode recognition stops on severe heat; it never reduces PUBG graphics or FPS. Battery reports use start/end observations and may miss intermediate charging or heat events. Landing calculations use supplied coordinates and speeds; there is no live `JUMP NOW` cue or map feed, and Battle Royale evidence blocks the assistant.

### Approval and restore

Every change follows `Measure → Diagnose → Propose → Approve for test → Backup → Testing → Compare → Final approval`. The approved snapshot remains protected while a candidate is being tested. A candidate cannot become final without recorded comparison results and the player's explicit final approval. Every mutable workflow operation rechecks the automatic guard, including inside its transaction; revoked capture blocks final approval. Crash recovery retains the approved version, candidate, and previous backup.

**Current interaction limitation:** returning to SPIDER AIM closes the form guard because PUBG is no longer verified in the foreground. An interactive settings-write flow while PUBG stays foreground is not implemented. A future authorized overlay or verified session-review design is required; manual mode labels cannot bypass this limitation.

PUBG offers no settings integration in this project. Enter your actual current settings first, and manually apply or restore displayed values in PUBG's official settings UI. Backups contain the complete settings snapshot recorded in SPIDER AIM; they cannot copy unobservable PUBG files. Restore is immediate for SPIDER AIM records and manual for PUBG itself.

Aim stability and observed hit outcomes have priority. Faster sensitivity alone is not success. Network latency/jitter, reliable packet-loss evidence when available, FPS issues, heat, tactical errors, and inconclusive desync indicators are distinguished from sensitivity problems. No feature changes damage, packets, game memory/files, player speed, graphics, refresh rate, or FPS. There is no touch injection or automatic aiming, movement, recoil compensation, or parachute control.

### Build and APK

Clone the GitHub repository or use the existing local project with Flutter **3.35.7 stable**, Java **17**, and Android SDK, then run `bash scripts/verify.sh`. The APK output is `build/app/outputs/flutter-apk/app-release.apk`. The source configures development signing for sideload testing; production distribution and consistent update signatures require the owner's stable private release key.

On [GitHub Actions](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml), open a successful **Android APK** run and download **spider-aim-android-apk** from its Artifacts section. Verification logs are uploaded as **spider-aim-verification**, including failed-run logs when present. Artifacts are retained for 30 days. Check an actual workflow run before treating a build as validated.

The historical 2026-10-07 run provides the **previous revision's** [APK](https://github.com/abbady110/spider-aim-/actions/runs/37621731959/artifacts/11482581407) and [verification logs](https://github.com/abbady110/spider-aim-/actions/runs/37621731959/artifacts/11482581411); these artifacts expire on 2026-11-06. Current CI also runs `./gradlew :app:testReleaseUnitTest` after APK compilation and before upload, with a `native-capture-tests.log` report. Rerun the workflow for fresh revision-specific artifacts.

iOS native device sources are included; the bootstrap script fills missing Xcode project/assets from the pinned Flutter SDK without replacing those sources. Cross-app PUBG capture is not implemented on iOS: it requires a ReplayKit Broadcast Upload Extension and Apple provisioning. The iOS automatic guard remains fail-closed. iOS builds/signing require macOS and Xcode. Desktop/web and emulator deployment are unsupported; CI unit/widget tests do not imply emulator product support.

Read [Architecture](docs/ARCHITECTURE.md), [Safety](docs/SAFETY.md), and [Limitations](docs/LIMITATIONS.md) for the implementation boundaries and extension contracts. Gameplay data stays local; this version has no video upload or cloud analysis. SQLite contents rely on the OS sandbox/device encryption, not additional application-level database encryption.
