# Android floating calibration panel / لوحة المعايرة العائمة

## الاستخدام

1. امنح Usage Access وابدأ التقاط الشاشة بموافقة Android الرسمية من صفحة الأمان.
2. اضغط **إذن الظهور فوق التطبيقات الأخرى** وامنح الإذن لـSPIDER AIM في إعدادات النظام.
3. ارجع واضغط **إظهار لوحة المعايرة العائمة**، ثم افتح PUBG وأبقِه في المقدمة.
4. تبدأ الفقاعة مقفولة. عند تحقق تلقائي متعدد الإطارات من وضع مسموح، اضغط الفقاعة لفتح نماذج SPIDER AIM.
5. وثّق إعدادات البداية الحقيقية، وسجّل عيناتك الفعلية، وراجع اقتراحًا مدعومًا بالدليل. الموافقة على التجربة تنشئ Backup ونسخة TESTING فقط.
6. طبّق القيم بنفسك في إعدادات PUBG الرسمية، واختبر في Warehouse/Arena/Unranked. أدخل نتائج المقارنة، ثم اختر الاعتماد النهائي أو الرفض أو الاسترجاع.

اللوحة تتعامل مع سجلات SPIDER AIM فقط. لا تضغط أزرار PUBG ولا تعدّل التصويب أو الحركة أو ملفات اللعبة. إذن اللوحة مستقل عن التقاط الشاشة ولا يمنح وضعًا آمنًا. ظهور الطائرة أو النزول أو أي مؤشر تنافسي يقفل اللوحة فور رصده. فقد الإذن أو تغيّر التطبيق الأمامي أو تقادم الدليل يغلق النموذج؛ لا يُحفظ تلقائيًا.

يمكن تصغير النموذج إلى الفقاعة، أو إخفاء اللوحة، أو إيقاف الالتقاط من التطبيق وإشعار النظام. الرجوع إلى واجهة SPIDER AIM الرئيسية يظل يقفل نماذجها؛ اللوحة هي مسار الكتابة أثناء بقاء PUBG في المقدمة.

## Boundaries and validation

The optional Android panel uses official `SYSTEM_ALERT_WINDOW` special access and `TYPE_APPLICATION_OVERLAY`. Permission is granted explicitly in Android settings. The panel uses the existing Flutter engine/controller and SQLite writer; it does not create a second app, engine, database, or approved profile.

Native authorization independently checks the actual capture session, foreground PUBG, fresh distinct native frame proof, competitive latching, and a live Dart heartbeat. The Dart bridge validates opaque form tokens against capture session, device, approved version, and trial state, and sends all writes through the existing transactional workflow. Neither permission nor a manually supplied mode can unlock it.

The window is `FLAG_SECURE` so its labels and forms are excluded from screen capture and cannot become game-mode evidence. The compact panel leaves game HUD space visible. If a device blanks more of the capture, or the panel covers required HUD evidence, authorization expires and the form closes. There is no bypass for that device behavior. Physical-device tests must verify this behavior, rotation, keyboard interaction, lifecycle revocation, recognition accuracy, and capture/overlay battery overhead.

Metrics and PUBG settings are still entered and applied manually. The panel does not implement automatic combat analysis or server-confirmed hit telemetry. Cross-app capture and this panel remain unavailable on iOS.

Install a new APK as an update when its signature is compatible. If Android rejects a development-signed update, do not erase an existing app that contains approved settings or backups. A stable private release signing key is required for reliable updates; the repository must not contain that private key.

See [Verification](VERIFICATION.md) for the exact tested code revision and build evidence. A passing automated build does not establish physical-device usability or gameplay improvement.
