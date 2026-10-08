# SPIDER AIM

مدرّب محلي لمعايرة التصويب والتحكم باللمس في PUBG باستخدام Flutter، مخصص لهواتف وأجهزة Android اللوحية وiPhone وiPad. الملف الافتراضي **NON_GYRO / TOUCH_ONLY**، والجيروسكوب وجيروسكوب ADS معطّلان دائمًا داخل ملفات التطبيق.

الأولوية لثبات التصويب ونتائج الإصابات المقاسة، مع فصل أخطاء التحكم عن الشبكة والأداء والحرارة. قياسات التصويب والتحكم يدخلها اللاعب؛ أضيف التعرف التلقائي على وضع اللعب من الشاشة على Android بواسطة OCR محلي وقواعد تحفظية. لا توجد قراءة مباشرة لبيانات PUBG أو تأكيد من خوادمها للإصابات.

يتضمن الإصدار **1.0.1+2** لوحة Android عائمة للتسجيل والمراجعة أثناء بقاء PUBG في المقدمة. اجتاز هذا الإصدار التحقق الآلي والبناء؛ اختبار سلوك اللوحة ولوحة المفاتيح والالتقاط الآمن على أجهزة فعلية ما زال مطلوبًا.

**حالة التحقق:** اجتازت الشيفرة `f4fdde7728e573258b308824b57893fb47278d7e` التحليل بلا مشكلات و**214 اختبارًا**، وبُني APK بحجم **63.5 MB** ونجحت مهمة الاختبارات الأصلية في [التشغيل الناجح بتاريخ 2026-10-08](https://github.com/abbady110/spider-aim-/actions/runs/37736827044). أظهر فحص APK المبني إذن اللوحة `SYSTEM_ALERT_WINDOW` وأثبت غياب إذني `INTERNET` و`ACCESS_NETWORK_STATE`. [تنزيل APK الحالي](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532685466). اختبار الالتقاط وواجهات PUBG على أجهزة فعلية وقياس التحسن أثناء اللعب ما زال مطلوبًا؛ راجع [سجل التحقق](docs/VERIFICATION.md) والقيود أدناه.

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

**لوحة Android العائمة:** أضيف مسار للتسجيل والمراجعة أثناء بقاء PUBG في المقدمة، بإذن «الظهور فوق التطبيقات الأخرى» الرسمي والمنفصل. افتح اللوحة من صفحة الأمان بعد بدء الالتقاط؛ تبقى مقفولة حتى يتأكد الحارس تلقائيًا من الوضع الآمن. تستخدم نفس قاعدة البيانات ودورة Backup والموافقة والاختبار. الرجوع إلى واجهة SPIDER AIM الرئيسية يظل يقفل نماذجها. انظر [طريقة استخدام اللوحة وحدودها](docs/OVERLAY.md)؛ اختبارها على هاتف فعلي ما زال مطلوبًا.

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

APK المبني مخصص للتجربة والتثبيت الجانبي وفق إعداد توقيع التطوير الحالي؛ تحتاج الإصدارات الموزعة والتحديثات المتوافقة إلى مفتاح توقيع إصدار ثابت يحتفظ به المالك. **تأكد اختلاف شهادتي APK السابق (التشغيل 37723093465) والحالي، لذلك لا يمكن تثبيت الحالي كتحديث فوقه. لا تحذف النسخة المثبتة عند وجود بيانات أو الشك في وجودها؛ لا توجد حاليًا ميزة تصدير بيانات من تلك النسخة.** يمكن اختبار APK الجديد على جهاز لا يحتوي بيانات SPIDER AIM. تفاصيل الشهادتين في [سجل التحقق](docs/VERIFICATION.md). لا تُضف مفاتيح أو كلمات مرور إلى المستودع.

## تنزيل APK من GitHub Actions

افتح [Actions → Android APK](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml)، ثم أحدث تشغيل ناجح. من **Artifacts** نزّل `spider-aim-android-apk`، وفك ZIP للوصول إلى `app-release.apk`. يحتوي `spider-aim-verification` على سجلات التحليل والاختبارات والبناء والتغطية عند توفرها. يلزم تسجيل الدخول إلى GitHub لتنزيل Artifacts، ومدة الاحتفاظ 30 يومًا.

أحدث بناء مؤكد للإصدار **1.0.1+2** اكتمل في **2026-10-08 الساعة 06:23:05 UTC**: [APK الحالي](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532685466) و[سجلات التحقق](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532725356). حجم Artifact المضغوط **29,996,977 بايت** وينتهي الاحتفاظ به في **2026-11-07 الساعة 06:22:59 UTC**؛ حجم Artifact السجلات **13,198 بايت** وينتهي في **06:23:02 UTC** من اليوم نفسه. نتيجتا النسختين السابقتين، 184 و111 اختبارًا، محفوظتان تاريخيًا في [سجل التحقق](docs/VERIFICATION.md).

ينفّذ Workflow إعداد الأدوات، و`flutter pub get`، و`flutter analyze`، و`flutter test`، وبناء APK، ومهمة الاختبارات الأصلية `:app:testReleaseUnitTest`. يفحص أيضًا أذونات **APK الفعلي** باستخدام `aapt` ويمنع رفع Artifact إذا بقي إذن `INTERNET` أو `ACCESS_NETWORK_STATE`. أظهرت مخرجات الفحص إذن اللوحة الرسمي `SYSTEM_ALERT_WINDOW` دون إذني الشبكة. راجع نتيجة التشغيل وسجلاته، ومنها `native-capture-tests.log`؛ نجحت هذه الخطوات في التشغيل الحالي المرتبط أعلاه.

## البنية والخصوصية

طبقات مستقلة لمحركات القياس والتشخيص، وحارس الوضع، وإدارة ملفات الجهاز والإصدارات، وتخزين SQLite، وواجهات الجهاز الأصلية، وواجهة Flutter. انظر [Architecture](docs/ARCHITECTURE.md).

تُحفظ بيانات الجلسات والملفات محليًا. صور الالتقاط ونصوص OCR الخام مؤقتة في الذاكرة؛ لا تُحفظ ولا تُرسل عبر الشبكة. تنتقل مؤشرات دلالية مقتضبة إلى الحارس، وتُحرر الصور بعد المعالجة. نموذج ML Kit اللاتيني مضمّن، ولا يوجد رفع فيديو أو تحليل سحابي. لا تحفظ معرفات حساسة مثل IMEI. البيانات المحلية غير مشفرة على مستوى قاعدة البيانات؛ تعتمد حمايتها على sandbox وتشفير نظام التشغيل.

مراجع APIs الرسمية: [MediaProjection](https://developer.android.com/media/grow/media-projection)، [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)، [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).

---

## English

SPIDER AIM is a local Flutter aim-and-control calibration coach for physical Android phones/tablets and iPhone/iPad. The default policy is `NON_GYRO`, `TOUCH_ONLY`, gyroscope disabled, and ADS gyroscope disabled. Android is the first intended build-validation target.

Version **1.0.1+2** includes an optional Android floating panel for entry and review while PUBG remains foreground. This revision passed automated validation and APK compilation; physical-device panel, keyboard, and secure-capture behavior still requires testing.

**Verification status:** revision `f4fdde7728e573258b308824b57893fb47278d7e` passed analysis with no issues and **214 tests**, built a **63.5 MB APK**, and passed the native test task in the [successful 2026-10-08 run](https://github.com/abbady110/spider-aim-/actions/runs/37736827044). The built APK permission output includes `SYSTEM_ALERT_WINDOW`; the audit confirmed that `INTERNET` and `ACCESS_NETWORK_STATE` are absent. [Download the current APK](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532685466). Real-device capture, PUBG HUD/layout validation, and measured gameplay improvement remain outstanding. See [Verification](docs/VERIFICATION.md) and the interaction limitations below.

The source implements an Arabic RTL dark interface, per-device profiles, official-API device/battery/thermal observations, weapon/scope/attachment/distance calibration contexts, evidence-based recommendations, movement/throwables review, death and hit-registration differential diagnostics, battery reports, and a local SQLite-backed settings-version workflow.

Coaching metrics still use structured player-entered evidence. Android now has an authorized screen-based mode-recognition pipeline: official MediaProjection consent, a visible media-projection foreground service, Usage Access granted in Android settings to verify the foreground PUBG package, and bundled on-device Latin ML Kit OCR. Frames have a 960-pixel maximum long edge and a minimum two-second sampling interval; only one OCR task runs at a time. No raw screen pixels or OCR text are persisted or sent over the network.

The guard requires at least four distinct pixel fingerprints across six seconds, consistent independent safe indicators, and a heuristic score of at least 0.95. Evidence expires after 12 seconds. The six states are `TRAINING_SAFE`, `WAREHOUSE_SAFE`, `ARENA_SAFE`, `SAFE_UNRANKED`, `COMPETITIVE_BLOCKED`, and `UNKNOWN_BLOCKED`. A credible Ranked/Battle Royale cue at 0.80 or above immediately latches the competitive lock and shuts down pixel/OCR work while retaining the service/session stop notification. Ambiguity, missing consent, unverified foreground, old or frozen frames block access. Manual historical selections are read-only and cannot authorize operations. Android 14 uses full-display capture consent to avoid analyzing an unrelated selected app window; notification permission is requested where Android requires it.

The confidence score is not an empirically established probability. Current Latin OCR/HUD rules still need real-device, locale, and layout validation. Unsupported Arabic game UI or HUD layouts remain unknown. Screen mode recognition does not implement automatic aim/video/death measurement or establish server-confirmed game telemetry.

Proposal notices remain in-app; the separate Android foreground-service notification provides a capture stop action. Low-rate mode recognition stops on severe heat; it never reduces PUBG graphics or FPS. Battery reports use start/end observations and may miss intermediate charging or heat events. Landing calculations use supplied coordinates and speeds; there is no live `JUMP NOW` cue or map feed, and Battle Royale evidence blocks the assistant.

### Approval and restore

Every change follows `Measure → Diagnose → Propose → Approve for test → Backup → Testing → Compare → Final approval`. The approved snapshot remains protected while a candidate is being tested. A candidate cannot become final without recorded comparison results and the player's explicit final approval. Every mutable workflow operation rechecks the automatic guard, including inside its transaction; revoked capture blocks final approval. Crash recovery retains the approved version, candidate, and previous backup.

**Android floating panel:** an optional official overlay now provides entry/review forms while PUBG remains foreground. Its separate special-access permission cannot unlock the guard. The panel uses the existing controller and SQLite workflow, including backups, trial consent, actual test comparison, and final approval. Returning to the main SPIDER AIM activity still locks its forms. Native window/keyboard/HUD behavior requires physical-device validation; see [Overlay usage and boundaries](docs/OVERLAY.md).

PUBG offers no settings integration in this project. Enter your actual current settings first, and manually apply or restore displayed values in PUBG's official settings UI. Backups contain the complete settings snapshot recorded in SPIDER AIM; they cannot copy unobservable PUBG files. Restore is immediate for SPIDER AIM records and manual for PUBG itself.

Aim stability and observed hit outcomes have priority. Faster sensitivity alone is not success. Network latency/jitter, reliable packet-loss evidence when available, FPS issues, heat, tactical errors, and inconclusive desync indicators are distinguished from sensitivity problems. No feature changes damage, packets, game memory/files, player speed, graphics, refresh rate, or FPS. There is no touch injection or automatic aiming, movement, recoil compensation, or parachute control.

### Build and APK

Clone the GitHub repository or use the existing local project with Flutter **3.35.7 stable**, Java **17**, and Android SDK, then run `bash scripts/verify.sh`. The APK output is `build/app/outputs/flutter-apk/app-release.apk`. The source configures development signing for sideload testing; production distribution and consistent update signatures require the owner's stable private release key. **The previous APK (run 37723093465) and current APK have confirmed different signing certificates, preventing an in-place update. Preserve the installed app if it contains data or its contents are uncertain; that version has no data-export feature.** Test the new APK on a device without existing SPIDER AIM data. Public certificate evidence is in [Verification](docs/VERIFICATION.md).

On [GitHub Actions](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml), open a successful **Android APK** run and download **spider-aim-android-apk** from its Artifacts section. Verification logs are uploaded as **spider-aim-verification**, including failed-run logs when present. Artifacts are retained for 30 days. Check an actual workflow run before treating a build as validated.

The latest verified run for **1.0.1+2** completed **2026-10-08 at 06:23:05 UTC** and provides the [current APK](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532685466) and [verification logs](https://github.com/abbady110/spider-aim-/actions/runs/37736827044/artifacts/11532725356). The APK artifact is **29,996,977 compressed bytes** and expires **2026-11-07 at 06:22:59 UTC**; the verification artifact is **13,198 compressed bytes** and expires at **06:23:02 UTC** that day. The previous 184-test and 111-test results are retained as history in [Verification](docs/VERIFICATION.md).

CI runs `./gradlew :app:testReleaseUnitTest` after APK compilation, preserving `native-capture-tests.log`. It also audits the actual built APK with `aapt` and refuses artifact upload if `INTERNET` or `ACCESS_NETWORK_STATE` survives manifest merging. The output lists the official `SYSTEM_ALERT_WINDOW` permission without either network permission. Both the native test task and APK permission audit passed in the linked current run.

iOS native device sources are included; the bootstrap script fills missing Xcode project/assets from the pinned Flutter SDK without replacing those sources. Cross-app PUBG capture is not implemented on iOS: it requires a ReplayKit Broadcast Upload Extension and Apple provisioning. The iOS automatic guard remains fail-closed. iOS builds/signing require macOS and Xcode. Desktop/web and emulator deployment are unsupported; CI unit/widget tests do not imply emulator product support.

Read [Architecture](docs/ARCHITECTURE.md), [Safety](docs/SAFETY.md), and [Limitations](docs/LIMITATIONS.md) for the implementation boundaries and extension contracts. Gameplay data stays local; this version has no video upload or cloud analysis. SQLite contents rely on the OS sandbox/device encryption, not additional application-level database encryption.
