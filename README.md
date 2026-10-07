# SPIDER AIM

مدرّب محلي لمعايرة التصويب والتحكم باللمس في PUBG باستخدام Flutter، مخصص لهواتف وأجهزة Android اللوحية وiPhone وiPad. الملف الافتراضي **NON_GYRO / TOUCH_ONLY**، والجيروسكوب وجيروسكوب ADS معطّلان دائمًا داخل ملفات التطبيق.

الأولوية لثبات التصويب ونتائج الإصابات المقاسة، مع فصل أخطاء التحكم عن الشبكة والأداء والحرارة. هذه نسخة مدرّب مبنية على أدلة يدخلها اللاعب؛ لا يوجد نموذج رؤية مدرّب أو قراءة مباشرة لبيانات PUBG أو تأكيد من خوادمها للإصابات.

**حالة التسليم الحالية:** كُتبت الشيفرة وملفات الاختبار وWorkflow محليًا، لكن بيئة التنفيذ لا تحتوي Flutter/Dart أو Android SDK، ولم يُنفّذ `flutter analyze` أو `flutter test` أو بناء APK. منع اتصال البيئة تنزيل الأدوات، وأعادت محاولة كتابة GitHub الخطأ `403 Resource not accessible by integration`. لم تُرفع التغييرات أو يُنشأ Artifact على GitHub. لذلك لم تتحقق شروط اكتمال البناء بعد. راجع [سجل التحقق](docs/VERIFICATION.md).

## ما نُفّذ في الشيفرة — بانتظار التحقق بالبناء

- واجهة عربية RTL داكنة ومتجاوبة، وملف مستقل لكل جهاز.
- اكتشاف معلومات الجهاز والشاشة والبطارية والحالة الحرارية عبر APIs عامة متاحة. القيم غير المتاحة تبقى `UNKNOWN`، خصوصًا معدل أخذ عينات اللمس وFPS الخاص بلعبة أخرى.
- ملفات معايرة مستقلة حسب السلاح والسكوب والملحقات والمسافة، وقياسات يدوية موثقة المصدر، وتحليل أنماط متعددة العينات.
- اقتراحات تشرح المشكلة والسبب والدليل وعدد العينات والقيمة الحالية والمقترحة والأثر المتوقع والمقايضة.
- دورة موافقة على التجربة، وBackup كامل لبيانات الإعدادات المسجلة، ونسخة تجريبية، ومقارنة، ثم موافقة نهائية منفصلة.
- تخزين SQLite محلي مع إصدارات مخطط قاعدة البيانات، وسجل الإصدارات والنسخ الاحتياطية ونتائج الاختبارات، واستعادة بيانات النسخة السابقة.
- تشخيص إرشادي للإصابات والوفيات، ومعايرة الحركة والقنابل، وتقارير بطارية، وحسابات هبوط مبنية على مدخلات اللاعب.
- ملف GitHub Actions لإجراء التحليل والاختبارات وبناء Android APK عند رفع المشروع وتشغيله بنجاح؛ لا يوجد Artifact منشور حاليًا.

## حدود مهمة

لا توفر PUBG هنا API عامة لقراءة إعداداتها أو تعديلها أو إثبات وضع المباراة. لذلك:

1. **التطبيق اليدوي إلزامي:** يعرض SPIDER AIM القيم، ويغيّر اللاعب إعدادات PUBG بنفسه عبر واجهتها الرسمية. Backup يحفظ الإعدادات التي سجلها اللاعب في SPIDER AIM، وليس ملفات PUBG غير القابلة للقراءة. يجب إدخال إعدادات البداية كاملة ودقيقة.
2. **الاسترجاع داخل SPIDER AIM فوري؛ داخل PUBG يدوي:** يسترجع التطبيق سجل الإعدادات ويعرض القيم التي يجب إعادة تطبيقها في اللعبة. لا يدّعي إعادة ضبط اللعبة تلقائيًا.
3. **Ranked مغلق وUNKNOWN مغلق:** التحليل الحي والتقاط الشاشة والتحليل الخلفي العابر للتطبيقات غير مفعلة لغياب وسيلة موثوقة تثبت وضع اللعبة. إعلان المستخدم لنوع جلسة سابقة يتيح مراجعتها اليدوية فقط؛ لا يمثل اكتشافًا آليًا أو تحققًا من وضع مباراة حية.
4. لا يوجد ضمان لتحسن Hit Registration؛ لا يستطيع التطبيق إجبار الخادم على تسجيل إصابة، أو معرفة السبب الحقيقي للـDesync من بيانات غير متاحة. النتيجة غير المدعومة بدليل هي `INCONCLUSIVE`.
5. لا يعدّل التطبيق سرعة اللاعب أو الضرر أو ملفات اللعبة أو الشبكة، ولا يتحكم بالتصويب والحركة والرمي والمظلة. لا يستخدم Accessibility أو Root أو Jailbreak أو APIs خاصة.
6. لا يُخفض FPS أو جودة الرسومات أو معدل تحديث اللعبة تلقائيًا. تخفيف الحمل يخص عمل SPIDER AIM نفسه.
7. لا يوجد دعم لسطح المكتب أو الويب أو المحاكيات. اختبارات الوحدة والواجهة تعمل على بيئة CI، ولا تعني دعم المحاكيات كمنصة تشغيل.
8. Android هو مسار البناء والتحقق الأول. بناء وتوقيع iOS يتطلبان macOS وXcode وفريق Apple Developer؛ لم يختبر iOS على جهاز فعلي ضمن CI الخاص بـAndroid.
9. الإشعارات الحالية رسائل محفوظة داخل واجهة SPIDER AIM، وليست إشعارات نظام أو Push. خطة خفض حمل التحليل موجودة كسياسة قابلة للاستخدام؛ لا توجد خدمة التقاط شاشة أو جدولة تحليل خلفي فعالة.
10. تقرير البطارية يعتمد على قراءات البداية والنهاية؛ لا يرصد بالضرورة الأحداث الحرارية أو الشحن بين القراءتين. مساعد الهبوط مراجعة هندسية تدريبية من مدخلاتك، ولا يصدر أمر قفز حيًا أو يختار نقطة هبوط من خريطة غير متاحة.

راجع [حدود القدرات ومصادر البيانات](docs/LIMITATIONS.md) و[قواعد السلامة](docs/SAFETY.md).

## دورة الاستخدام

1. افتح ملف جهازك وأدخل إعدادات PUBG الحالية بدقة. لا تُنسخ حساسية هاتفك إلى جهاز لوحي.
2. اختر جلسة تدريب أو Warehouse غير مصنفة أو Unranked مؤكدة من جانبك لمراجعة نتائجها اليدوية. أي وضع Ranked أو غير معروف يمنع مسار المعايرة.
3. اجمع عدة محاولات متقاربة الظروف لنفس السلاح والسكوب والملحقات والمسافة. أدخل النتائج الحقيقية، ولا تعامل القياسات اليدوية على أنها telemetry آلية.
4. راجع الاقتراح، ثم اختر موافقة على التجربة أو رفض أو تأجيل. عند الموافقة يحفظ التطبيق Backup قبل إنشاء النسخة التجريبية.
5. طبّق القيم بنفسك داخل PUBG، واختبرها في وضع غير مصنف. سجّل النتائج المقارنة. لا يصبح TESTING معتمدًا تلقائيًا.
6. اعتمد بعد اجتياز المقارنة وموافقتك النهائية، أو أعد الاختبار أو ارفض أو استرجع النسخة السابقة يدويًا داخل PUBG.

## البناء

المتطلبات: Flutter **3.35.7 stable**، Java **17**، وAndroid SDK. البناء محصور في ARM/ARM64، للهواتف والأجهزة اللوحية الفعلية.

استخدم مجلد المشروع المحلي الذي يحتوي هذه التغييرات. أو نفّذ أوامر Clone أدناه بعد رفع التغييرات إلى GitHub؛ المستودع البعيد لم يستقبلها خلال هذا التسليم.

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

APK الناتج عند نجاح البناء سيكون مخصصًا للتجربة والتثبيت الجانبي وفق إعداد التوقيع الحالي؛ يحتاج إصدار المتجر إلى مفتاح توقيع إصدار خاص يحتفظ به المالك. لا يوجد APK مبني ضمن هذا التسليم. لا تُضف مفاتيح أو كلمات مرور إلى المستودع.

## تنزيل APK من GitHub Actions

افتح [Actions → Android APK](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml)، ثم أحدث تشغيل ناجح. من **Artifacts** نزّل `spider-aim-android-apk`، وفك ZIP للوصول إلى `app-release.apk`. يحتوي `spider-aim-verification` على سجلات التحليل والاختبارات والبناء والتغطية عند توفرها. يلزم تسجيل الدخول إلى GitHub لتنزيل Artifacts، ومدة الاحتفاظ 30 يومًا.

ينفّذ Workflow: Checkout → Java/Android/Flutter setup → `flutter pub get` → `flutter analyze` → `flutter test` → APK build → artifact upload. وجود ملف Workflow وحده ليس إثبات نجاح البناء؛ راجع نتيجة التشغيل الفعلية وسجلاته.

## البنية والخصوصية

طبقات مستقلة لمحركات القياس والتشخيص، وحارس الوضع، وإدارة ملفات الجهاز والإصدارات، وتخزين SQLite، وواجهات الجهاز الأصلية، وواجهة Flutter. انظر [Architecture](docs/ARCHITECTURE.md).

تُحفظ بيانات الجلسات والملفات محليًا. لا يوجد رفع لفيديو اللعب أو خدمة تحليل سحابية. لا تحفظ معرفات جهاز حساسة مثل IMEI. البيانات المحلية غير مشفرة على مستوى قاعدة البيانات في هذا الإصدار؛ تعتمد حماية الملفات على sandbox والتشفير الذي يوفره نظام التشغيل.

---

## English

SPIDER AIM is a local Flutter aim-and-control calibration coach for physical Android phones/tablets and iPhone/iPad. The default policy is `NON_GYRO`, `TOUCH_ONLY`, gyroscope disabled, and ADS gyroscope disabled. Android is the first intended build-validation target.

**Current delivery status:** source, tests, and the CI workflow have been implemented locally, but no Flutter/Dart or Android SDK is installed in the execution environment. `flutter analyze`, `flutter test`, and APK compilation have **not run**. Environment connectivity prevented tool installation, and the GitHub write attempt returned `403 Resource not accessible by integration`. No changes or APK artifacts have been uploaded to GitHub. The build definition of done is therefore **not yet met**. See [Verification](docs/VERIFICATION.md).

The source implements an Arabic RTL dark interface, per-device profiles, official-API device/battery/thermal observations, weapon/scope/attachment/distance calibration contexts, evidence-based recommendations, movement/throwables review, death and hit-registration differential diagnostics, battery reports, and a local SQLite-backed settings-version workflow. These implementations still require compilation, test execution, and physical-device validation.

The implemented coaching uses structured player-entered evidence and deterministic analysis. It is not a trained computer-vision model, game telemetry integration, aimbot, or external PUBG controller. Unknown measurements remain unknown. No live game-mode verification provider is available: live capture/background/game analysis stays fail-closed. A user's declaration of a past Unranked session is explicitly a manual review context, not automatic game-mode detection.

Notifications are persisted in-app notices, not OS push notifications. Adaptive battery scheduling is a policy hook, not an active background capture service. Battery reports use start/end observations and may miss intermediate charging or heat events. Landing calculations are retrospective estimates from supplied coordinates and speeds; there is no live `JUMP NOW` cue or live map feed.

### Approval and restore

Every change follows `Measure → Diagnose → Propose → Approve for test → Backup → Testing → Compare → Final approval`. The approved snapshot remains protected while a candidate is being tested. A candidate cannot become final without recorded comparison results and the player's explicit final approval. Ranked and unknown contexts block calibration operations. Crash recovery retains the approved version, candidate, and previous backup.

PUBG offers no settings integration in this project. Enter your actual current settings first, and manually apply or restore displayed values in PUBG's official settings UI. Backups contain the complete settings snapshot recorded in SPIDER AIM; they cannot copy unobservable PUBG files. Restore is immediate for SPIDER AIM records and manual for PUBG itself.

Aim stability and observed hit outcomes have priority. Faster sensitivity alone is not success. Network latency/jitter, reliable packet-loss evidence when available, FPS issues, heat, tactical errors, and inconclusive desync indicators are distinguished from sensitivity problems. No feature changes damage, packets, game memory/files, player speed, graphics, refresh rate, or FPS. There is no touch injection or automatic aiming, movement, recoil compensation, or parachute control.

### Build and APK

Use the delivered local project with Flutter **3.35.7 stable**, Java **17**, and Android SDK, then run `bash scripts/verify.sh`. The clone commands above apply once these changes have actually been pushed. On successful compilation, the APK will be `build/app/outputs/flutter-apk/app-release.apk`. The source configures development signing for sideload testing; production distribution requires the owner's private release signing configuration. No APK has been produced in this delivery.

On [GitHub Actions](https://github.com/abbady110/spider-aim-/actions/workflows/android.yml), open a successful **Android APK** run and download **spider-aim-android-apk** from its Artifacts section. Verification logs are uploaded as **spider-aim-verification**, including failed-run logs when present. Artifacts are retained for 30 days. Check an actual workflow run before treating a build as validated.

iOS native sources are included; the bootstrap script fills missing Xcode project/assets from the pinned Flutter SDK without replacing those sources. iOS builds/signing require macOS, Xcode, and Apple provisioning. Desktop/web and emulator deployment are unsupported. Unit/widget tests in CI are supported and do not imply emulator product support.

Read [Architecture](docs/ARCHITECTURE.md), [Safety](docs/SAFETY.md), and [Limitations](docs/LIMITATIONS.md) for the implementation boundaries and extension contracts. Gameplay data stays local; this version has no video upload or cloud analysis. SQLite contents rely on the OS sandbox/device encryption, not additional application-level database encryption.
