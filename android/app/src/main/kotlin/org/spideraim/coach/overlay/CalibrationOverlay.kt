package org.spideraim.coach.overlay

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.InputFilter
import android.text.InputType
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import java.text.DateFormat
import java.util.Date
import io.flutter.plugin.common.MethodChannel
import org.spideraim.coach.capture.CaptureEvents
import org.spideraim.coach.capture.PubgForegroundVerifier

/** Tiny authorized Android view using the existing Flutter engine and writer. */
class CalibrationOverlay(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val windows = activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val foreground = PubgForegroundVerifier(activity.applicationContext)
    private val policy = OverlayAuthorizationPolicy(
        clockMs = { System.currentTimeMillis() }, elapsedClockMs = { SystemClock.elapsedRealtime() })
    private var root: LinearLayout? = null
    private var bubbleLabel: TextView? = null
    private var panel: LinearLayout? = null
    private var state: Map<String, Any?> = emptyMap()
    private var expanded = false
    private var pending = false
    private var generation = 0L
    private var destroyed = false
    private var requestTimeout: Runnable? = null
    private var activeFormId: String? = null
    private var formSubmit: Button? = null
    private val inputs = mutableListOf<FieldInput>()
    private var layout: WindowManager.LayoutParams? = null
    private var displayWidth = 0
    private var displayHeight = 0
    private var readOnlyPanel = false
    private var statusText: TextView? = null
    private var feedback: TextView? = null
    private var clearFeedback: Runnable? = null

    private data class FieldInput(val field: Map<String, Any?>, val read: () -> Any?)

    private val proofObserver: (Map<String, Any?>) -> Unit = { event ->
        try {
        when (event["type"]) {
            "started" -> (event["sessionId"] as? String)?.let { policy.nativeStarted(it) }
            "stopped", "prepared" -> {
                policy.nativeStopped()
            }
            "frame" -> {
                @Suppress("UNCHECKED_CAST")
                val cues = (event["cues"] as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()
                policy.nativeFrame(event["sessionId"] as? String ?: "",
                    event["captureAuthorized"] == true, event["foregroundVerified"] == true,
                    event["foregroundPackage"] as? String,
                    (event["timestampMs"] as? Number)?.toLong() ?: 0L,
                    (event["sequence"] as? Number)?.toLong() ?: 0L,
                    event["frameFingerprint"] as? String, cues)
            }
        }
        } catch (_: Exception) {
            // Overlay failure must neither keep a form writable nor prevent the
            // primary Flutter guard from receiving the native capture event.
            policy.nativeStopped()
        }
    }

    private val observer: (Map<String, Any?>) -> Unit = { event ->
        try {
            if (event["type"] == "stopped" || event["type"] == "prepared") hide()
            refreshGate()
        } catch (_: Exception) { hide() }
    }

    private val gateTick = object : Runnable {
        override fun run() {
            if (destroyed || root == null) return
            if (!Settings.canDrawOverlays(activity)) { hide(); return }
            onDisplayChanged()
            refreshGate()
            main.postDelayed(this, 750L)
        }
    }

    init {
        CaptureEvents.addImmediateProofObserver(proofObserver)
        CaptureEvents.addObserver(observer)
    }

    fun updateState(value: Map<String, Any?>) {
        state = value.toMap()
        policy.updateState(state)
        refreshGate()
    }

    fun show(): Map<String, Any?> {
        if (destroyed || !Settings.canDrawOverlays(activity)) {
            return mapOf("visible" to false, "reason" to "OVERLAY_PERMISSION_REQUIRED")
        }
        if (!CaptureEvents.running || CaptureEvents.sessionId.isNullOrBlank()) {
            return mapOf("visible" to false, "reason" to "CAPTURE_SESSION_REQUIRED")
        }
        if (root != null) return mapOf("visible" to true)
        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = rounded(0xee111827.toInt())
        }
        val label = TextView(activity).apply {
            setTextColor(Color.WHITE)
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(5), dp(6), dp(5), dp(6))
            setOnClickListener {
                if (expanded) collapse() else {
                    expanded = true
                    if (authorized()) renderMenu() else renderStatus()
                }
            }
        }
        container.addView(label, LinearLayout.LayoutParams(dp(78), dp(48)))
        val feedbackView = text("").apply { visibility = View.GONE; maxLines = 3 }
        container.addView(feedbackView, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT))
        feedback = feedbackView
        root = container
        bubbleLabel = label
        val params = WindowManager.LayoutParams(dp(94), WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT).apply {
            // Keep PUBG's usual top-right map label and top-center score HUD free.
            gravity = Gravity.LEFT or Gravity.BOTTOM
            x = dp(8)
            y = dp(52)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        layout = params
        return try {
            windows.addView(container, params)
            refreshGate()
            main.post(gateTick)
            mapOf("visible" to true)
        } catch (_: Exception) {
            root = null
            bubbleLabel = null
            layout = null
            mapOf("visible" to false, "reason" to "OVERLAY_WINDOW_UNAVAILABLE")
        }
    }

    fun hide(): Map<String, Any?> {
        generation++
        pending = false
        activeFormId = null
        inputs.clear()
        formSubmit = null
        main.removeCallbacks(gateTick)
        clearFeedback?.let { main.removeCallbacks(it) }
        clearFeedback = null
        requestTimeout?.let { main.removeCallbacks(it) }
        requestTimeout = null
        root?.let { view ->
            (activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .hideSoftInputFromWindow(view.windowToken, 0)
            try { windows.removeViewImmediate(view) } catch (_: Exception) { /* Already removed by Android. */ }
        }
        root = null
        bubbleLabel = null
        feedback = null
        panel = null
        statusText = null
        readOnlyPanel = false
        layout = null
        expanded = false
        return mapOf("visible" to false)
    }

    fun destroy() {
        destroyed = true
        CaptureEvents.removeImmediateProofObserver(proofObserver)
        CaptureEvents.removeObserver(observer)
        hide()
    }

    @Suppress("DEPRECATION")
    fun onDisplayChanged() {
        val view = root ?: return
        val params = layout ?: return
        val metrics = DisplayMetrics().also { windows.defaultDisplay.getRealMetrics(it) }
        if (metrics.widthPixels == displayWidth && metrics.heightPixels == displayHeight) return
        displayWidth = metrics.widthPixels
        displayHeight = metrics.heightPixels
        params.width = if (expanded) minOf(dp(400), (displayWidth * .40).toInt()).coerceAtLeast(1) else dp(94)
        params.height = if (expanded) (displayHeight * .72).toInt() else WindowManager.LayoutParams.WRAP_CONTENT
        params.x = params.x.coerceIn(0, maxOf(0, displayWidth - params.width))
        params.y = params.y.coerceIn(0, maxOf(0, displayHeight - if (expanded) params.height else dp(64)))
        try { windows.updateViewLayout(view, params) } catch (_: Exception) { hide() }
    }

    private fun authorized(): Boolean {
        val proof = foreground.read()
        return Settings.canDrawOverlays(activity) && policy.authorize(CaptureEvents.running,
            CaptureEvents.sessionId, proof.packageName, proof.verified)
    }

    private fun refreshGate() {
        if (root == null) return
        if (!CaptureEvents.running) { hide(); return }
        val allowed = authorized()
        val mode = if (policy.competitiveLatched) "COMPETITIVE_BLOCKED" else state["mode"] as? String ?: "UNKNOWN_BLOCKED"
        val confidence = ((state["confidence"] as? Number)?.toDouble() ?: 0.0)
            .takeIf { it.isFinite() && it in 0.0..1.0 } ?: 0.0
        val label = when (mode) {
            "TRAINING_SAFE" -> "تدريب"
            "WAREHOUSE_SAFE" -> "مخزن"
            "ARENA_SAFE" -> "أرينا"
            "SAFE_UNRANKED" -> "غير مصنف"
            "COMPETITIVE_BLOCKED" -> "محظور"
            else -> "غير معروف"
        }
        bubbleLabel?.text = "$label\n${(confidence * 100).toInt()}%${if (allowed) "" else " 🔒"}"
        bubbleLabel?.contentDescription = "$mode — ${(confidence * 100).toInt()}%"
        bubbleLabel?.setTextColor(if (allowed) 0xff5eead4.toInt() else 0xfffca5a5.toInt())
        if (!allowed && expanded && !readOnlyPanel && !(pending && policy.lastReason == "STATE_BUSY_OR_INVALID" && state["busy"] == true)) {
            // No open form survives an ambiguous frame, stale heartbeat, stopped
            // projection, changed foreground, or a competitive cue.
            renderStatus()
        }
        statusText?.text = statusDescription(allowed)
        formSubmit?.isEnabled = allowed && !pending
    }

    private fun collapse() {
        generation++
        expanded = false
        activeFormId = null
        inputs.clear()
        formSubmit = null
        panel?.let { root?.removeView(it) }
        panel = null
        statusText = null
        readOnlyPanel = false
        val params = layout ?: return
        params.width = dp(94)
        params.height = WindowManager.LayoutParams.WRAP_CONTENT
        params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        root?.let { view ->
            (activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .hideSoftInputFromWindow(view.windowToken, 0)
            try { windows.updateViewLayout(view, params) } catch (_: Exception) { hide() }
        }
    }

    private fun newPanel(title: String): LinearLayout {
        panel?.let { root?.removeView(it) }
        statusText = null
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
            setPadding(dp(4), dp(4), dp(4), dp(4))
        }
        val scroll = ScrollView(activity).apply { addView(body); isFillViewport = true }
        val outer = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(text(title, 16f))
            addView(button("تصغير") { collapse() })
            addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
            addView(button("إخفاء النافذة") { request("hideOverlay", emptyMap()) })
        }
        panel = outer
        val params = requireNotNull(layout)
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windows.defaultDisplay.getRealMetrics(metrics)
        params.width = minOf(dp(400), (metrics.widthPixels * .40).toInt()).coerceAtLeast(1)
        params.height = (metrics.heightPixels * .72).toInt()
        params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        root?.addView(outer, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        try { root?.let { windows.updateViewLayout(it, params) } } catch (_: Exception) { hide() }
        return body
    }

    private fun renderMenu() {
        if (!authorized()) { collapse(); return }
        readOnlyPanel = false
        activeFormId = null
        inputs.clear()
        val body = newPanel("SPIDER AIM — المعايرة الآمنة")
        statusText = text(statusDescription(true)).also { body.addView(it) }
        (state["summary"] as? String)?.takeIf { it.isNotBlank() }?.let { body.addView(text(it)) }
        body.addView(text("الإعدادات داخل PUBG تُطبق يدويًا. الموافقة والنسخ والاختبارات تُحفظ في التطبيق."))
        body.addView(text("إذا منع جهازك التحقق من الشاشة عند ظهور هذه النافذة، تُغلق المعايرة تلقائيًا ويبقى القفل فعالًا."))
        val menus = state["menus"] as? List<*> ?: state["menu"] as? List<*> ?: emptyList<Any>()
        menus.take(20).forEach { raw ->
            val entry = raw as? Map<*, *> ?: return@forEach
            val action = (entry["action"] ?: entry["id"]) as? String ?: return@forEach
            val label = entry["label"] as? String ?: return@forEach
            body.addView(button(label) { request(action, emptyMap()) }.apply {
                isEnabled = entry["enabled"] != false && !pending
            })
        }
    }

    private fun renderStatus() {
        // A blocked status view contains no form or mutation menu. It remains
        // readable while PUBG is foreground without reopening the main app.
        collapse()
        if (root == null) return
        expanded = true
        readOnlyPanel = true
        val body = newPanel("حالة الوضع المكتشف — عرض فقط")
        statusText = text(statusDescription(authorized())).also { body.addView(it) }
        body.addView(text("المعايرة مغلقة عند الشك أو عند فقدان التحقق. لا يوجد تجاوز يدوي للقفل."))
        body.addView(text("قد تمنع بعض الأجهزة التقاط الشاشة مع نافذة آمنة؛ عندها يبقى الوضع غير معروف ومقفولًا."))
    }

    private fun statusDescription(allowed: Boolean): String {
        val mode = if (policy.competitiveLatched) "COMPETITIVE_BLOCKED" else state["mode"] as? String ?: "UNKNOWN_BLOCKED"
        val confidence = ((state["confidence"] as? Number)?.toDouble() ?: 0.0)
            .takeIf { it.isFinite() && it in 0.0..1.0 } ?: 0.0
        val verified = (state["lastVerifiedMs"] as? Number)?.toLong()?.let {
            DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(it))
        } ?: "لم يتحقق"
        val evidence = (state["evidence"] as? List<*>)?.filterIsInstance<String>()?.take(8)
            ?.joinToString("\n• ") ?: "لا توجد أدلة موثوقة"
        return "الوضع: $mode\nالثقة: ${(confidence * 100).toInt()}%\nآخر تحقق: $verified\n" +
            "الأدلة:\n• $evidence\nالقفل: ${if (allowed) "المعايرة متاحة" else "مغلق"}\n${policy.lastReason}"
    }

    private fun request(action: String, payload: Map<String, Any?>) {
        if (action == "hideOverlay") {
            if (destroyed) return
            // Hiding is always available, including an in-flight save or lock.
            // Notify the same root engine so its visibility flag stays truthful.
            hide()
            channel.invokeMethod("request", mapOf("action" to action, "payload" to payload), object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            })
            return
        }
        if (destroyed || pending || !authorized()) { refreshGate(); return }
        pending = true
        formSubmit?.isEnabled = false
        val requestGeneration = generation
        val requestSession = CaptureEvents.sessionId
        val timeout = Runnable {
            if (!destroyed && pending && requestGeneration == generation) {
                pending = false
                generation++
                failed("لم يصل تأكيد الحفظ؛ راجع السجل قبل إعادة المحاولة.")
            }
        }
        requestTimeout = timeout
        main.postDelayed(timeout, 10_000L)
        channel.invokeMethod("request", mapOf("action" to action, "payload" to payload), object : MethodChannel.Result {
            override fun success(result: Any?) {
                main.removeCallbacks(timeout)
                if (requestTimeout === timeout) requestTimeout = null
                pending = false
                if (destroyed || root == null || requestGeneration != generation || requestSession != CaptureEvents.sessionId) return
                @Suppress("UNCHECKED_CAST")
                val response = result as? Map<String, Any?> ?: return failed("رد غير صالح من التطبيق.")
                @Suppress("UNCHECKED_CAST")
                (response["state"] as? Map<String, Any?>)?.let { updateState(it) }
                if (!authorized()) { collapse(); return }
                if (response["ok"] != true) {
                    failed((response["error"] ?: response["message"]) as? String ?: "لم يُحفظ التعديل.")
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val form = response["form"] as? Map<String, Any?>
                if (form != null) renderForm(form) else {
                    toast(response["message"] as? String ?: "تم حفظ النتيجة بأمان.")
                    renderMenu()
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                main.removeCallbacks(timeout)
                if (requestTimeout === timeout) requestTimeout = null
                pending = false
                if (!destroyed && requestGeneration == generation) failed(message ?: code)
            }
            override fun notImplemented() {
                main.removeCallbacks(timeout)
                if (requestTimeout === timeout) requestTimeout = null
                pending = false
                if (!destroyed && requestGeneration == generation) failed("اتصال التطبيق غير متاح؛ القفل مغلق.")
            }
        })
    }

    private fun failed(message: String) { toast(message); refreshGate() }

    private fun renderForm(form: Map<String, Any?>) {
        if (!authorized()) { collapse(); return }
        val id = form["id"] as? String ?: return failed("النموذج غير صالح.")
        val fields = form["fields"] as? List<*> ?: return failed("حقول النموذج غير متاحة.")
        if (fields.size > 80) return failed("عدد حقول النموذج يتجاوز حد النافذة.")
        activeFormId = id
        readOnlyPanel = false
        inputs.clear()
        val body = newPanel(form["title"] as? String ?: "المعايرة")
        statusText = text(statusDescription(true)).also { body.addView(it) }
        (form["notice"] as? String)?.let { body.addView(text(it)) }
        fields.forEach { raw ->
            @Suppress("UNCHECKED_CAST")
            val field = raw as? Map<String, Any?> ?: return@forEach
            val key = field["key"] as? String ?: return@forEach
            val label = field["label"] as? String ?: key
            when (field["type"]) {
                "checkbox" -> {
                    val check = CheckBox(activity).apply {
                        text = label; setTextColor(Color.WHITE)
                        isChecked = field["value"] == true
                    }
                    body.addView(check)
                    inputs += FieldInput(field) { check.isChecked }
                }
                "choice" -> {
                    val options = (field["options"] as? List<*>)?.mapNotNull { it as? Map<*, *> } ?: emptyList()
                    body.addView(text(label))
                    var selected: String? = null
                    val choices = RadioGroup(activity).apply {
                        orientation = RadioGroup.VERTICAL
                        layoutDirection = View.LAYOUT_DIRECTION_RTL
                    }
                    options.forEach { option ->
                        val optionValue = option["value"] as? String ?: return@forEach
                        val radio = RadioButton(activity).apply {
                            this.id = View.generateViewId()
                            text = option["label"] as? String ?: optionValue
                            textSize = 12f
                            setTextColor(Color.WHITE)
                            setOnClickListener { selected = optionValue }
                        }
                        choices.addView(radio)
                        if (field["value"] is String && optionValue == field["value"]) {
                            choices.check(radio.id)
                            selected = optionValue
                        }
                    }
                    // No PopupWindow: every option remains in our FLAG_SECURE
                    // window and cannot become a captured PUBG mode label.
                    body.addView(choices)
                    inputs += FieldInput(field) { selected }
                }
                "number", "text" -> {
                    body.addView(text(label))
                    val edit = EditText(activity).apply {
                        setTextColor(Color.WHITE); setHintTextColor(0xff9ca3af.toInt())
                        textSize = 13f
                        filters = arrayOf(InputFilter.LengthFilter(1000))
                        inputType = if (field["type"] == "number") InputType.TYPE_CLASS_NUMBER or
                            InputType.TYPE_NUMBER_FLAG_DECIMAL or InputType.TYPE_NUMBER_FLAG_SIGNED
                            else InputType.TYPE_CLASS_TEXT
                        imeOptions = android.view.inputmethod.EditorInfo.IME_FLAG_NO_EXTRACT_UI
                        field["value"]?.let { setText(it.toString()) }
                    }
                    body.addView(edit)
                    inputs += FieldInput(field) {
                        val value = edit.text.toString().trim()
                        if (field["type"] == "number") {
                            if (value.isEmpty()) null else value.toDoubleOrNull() ?: value
                        } else value
                    }
                }
            }
        }
        val submit = button(form["submitLabel"] as? String ?: "حفظ") { submitForm() }
        formSubmit = submit
        body.addView(submit)
        refreshGate()
    }

    private fun submitForm() {
        if (!authorized() || pending) { refreshGate(); return }
        val id = activeFormId ?: return
        val values = linkedMapOf<String, Any?>()
        for (input in inputs) {
            val value = input.read()
            val field = input.field
            val required = field["required"] == true
            val label = field["label"] as? String ?: "الحقل"
            if (required && (value == null || value == "" || (field["type"] == "checkbox" && value != true))) {
                toast("أكمل $label أولًا."); return
            }
            if (field["type"] == "number" && value != null) {
                val number = value as? Double
                if (number == null) { toast("أدخل رقمًا صحيحًا في $label."); return }
                val min = (field["min"] as? Number)?.toDouble()
                val max = (field["max"] as? Number)?.toDouble()
                if (!number.isFinite() || (min != null && number < min) || (max != null && number > max)) {
                    toast("قيمة $label خارج النطاق المسموح."); return
                }
            }
            values[field["key"] as? String ?: return] = value
        }
        request("submit", mapOf("formId" to id, "values" to values))
    }

    private fun text(value: String, size: Float = 12f) = TextView(activity).apply {
        text = value; textSize = size; setTextColor(Color.WHITE)
        setPadding(dp(3), dp(4), dp(3), dp(4))
    }

    private fun button(label: String, action: () -> Unit) = Button(activity).apply {
        text = label; textSize = 12f; isAllCaps = false
        setOnClickListener { action() }
    }

    private fun rounded(color: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(14).toFloat() }
    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
    private fun toast(value: String) {
        // Even feedback stays inside FLAG_SECURE; a separate system Toast could
        // expose our own text to the captured screen on some Android versions.
        val notice = feedback ?: return
        clearFeedback?.let { main.removeCallbacks(it) }
        notice.text = value
        notice.visibility = View.VISIBLE
        val clear = Runnable { feedback?.visibility = View.GONE }
        clearFeedback = clear
        main.postDelayed(clear, 5_000L)
    }
}
