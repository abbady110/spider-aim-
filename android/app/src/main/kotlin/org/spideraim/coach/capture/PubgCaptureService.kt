package org.spideraim.coach.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.WindowManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.Executor
import kotlin.math.roundToInt

/** Consented passive capture. The only outputs are semantic cues; no raw OCR leaves this class. */
class PubgCaptureService : Service() {
    companion object {
        const val ACTION_START = "org.spideraim.coach.capture.START"
        const val ACTION_STOP = "org.spideraim.coach.capture.STOP"
        const val EXTRA_SESSION = "sessionId"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_PROJECTION_DATA = "projectionData"
        private const val CHANNEL = "spider_aim_screen_recognition"
        private const val NOTIFICATION_ID = 4821
        private const val SAMPLE_INTERVAL_MS = 2_000L
        private const val LONG_EDGE_PX = 960
        private val COMPETITIVE_CUES = setOf("airplane", "flight_path", "jump", "follow",
            "free_fall", "parachute", "br_map", "ranked_label")
    }

    private val workerThread = HandlerThread("spider-aim-local-capture")
    private lateinit var worker: Handler
    private lateinit var foreground: PubgForegroundVerifier
    private lateinit var power: PowerManager
    private var projection: MediaProjection? = null
    private var reader: ImageReader? = null
    private var display: VirtualDisplay? = null
    private var recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private var session: String? = null
    private var sequence = 0L
    private var lastSampleElapsed = 0L
    private var previousFingerprint: String? = null
    private var previousRespawn = false
    private var processing = false
    private var competitiveSuspended = false
    private var capturedContentVisible = true
    @Volatile private var destroyed = false
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var width = 0
    private var height = 0
    private var densityDpi = 0
    private val workerExecutor = Executor { task -> if (!destroyed) worker.post(task) else task.run() }

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() { stopCapture("CAPTURE_PERMISSION_REVOKED") }

        override fun onCapturedContentResize(newWidth: Int, newHeight: Int) {
            if (Build.VERSION.SDK_INT >= 34 && !destroyed && newWidth > 0 && newHeight > 0) {
                resize(newWidth, newHeight)
            }
        }

        override fun onCapturedContentVisibilityChanged(isVisible: Boolean) {
            capturedContentVisible = isVisible
            if (!isVisible && !destroyed) {
                previousRespawn = false
                previousFingerprint = null
                emitUnavailable("CAPTURE_CONTENT_NOT_VISIBLE")
            }
        }
    }

    private val foregroundPoll = object : Runnable {
        override fun run() {
            if (destroyed || competitiveSuspended) return
            if (thermalTooHigh()) {
                stopCapture("THERMAL_SEVERE")
                return
            }
            val state = foreground.read()
            if (!state.verified) emitUnavailable(state.reason ?: "FOREGROUND_NOT_VERIFIED", state)
            worker.postDelayed(this, 1_000L)
        }
    }

    private val sampleTick = object : Runnable {
        override fun run() {
            if (destroyed || competitiveSuspended) return
            if (!processing && capturedContentVisible && foreground.read().verified) {
                // Attach only until the next image arrives. Keeping a full-time
                // surface would render 60+ capture frames/s merely to OCR one/2s.
                display?.surface = reader?.surface
            } else display?.surface = null
            worker.postDelayed(this, SAMPLE_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        workerThread.start()
        worker = Handler(workerThread.looper)
        foreground = PubgForegroundVerifier(applicationContext)
        power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val listener = PowerManager.OnThermalStatusChangedListener { status ->
                if (status >= PowerManager.THERMAL_STATUS_SEVERE) worker.post { stopCapture("THERMAL_SEVERE") }
            }
            thermalListener = listener
            power.addThermalStatusListener(listener)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            worker.post { stopCapture("STOPPED_BY_USER") }
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START || projection != null || session != null) {
            if (session == null) stopSelf()
            return START_NOT_STICKY
        }
        session = intent.getStringExtra(EXTRA_SESSION)
        val code = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_PROJECTION_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_PROJECTION_DATA)
        }
        if (session == null || data == null || code != android.app.Activity.RESULT_OK) {
            worker.post { stopCapture("CAPTURE_PERMISSION_MISSING") }
            return START_NOT_STICKY
        }
        try {
            val notification = createNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else startForeground(NOTIFICATION_ID, notification)
        } catch (_: Exception) {
            worker.post { stopCapture("FOREGROUND_SERVICE_UNAVAILABLE") }
            return START_NOT_STICKY
        }
        worker.post {
            try {
                if (!PubgForegroundVerifier.hasUsageAccess(applicationContext)) {
                    stopCapture("USAGE_ACCESS_REQUIRED")
                    return@post
                }
                if (thermalTooHigh()) {
                    stopCapture("THERMAL_SEVERE")
                    return@post
                }
                val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                projection = manager.getMediaProjection(code, data)
                projection?.registerCallback(projectionCallback, worker)
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
                densityDpi = metrics.densityDpi
                val size = scaledSize(metrics.widthPixels, metrics.heightPixels)
                width = size.first
                height = size.second
                reader = newReader(width, height)
                display = projection?.createVirtualDisplay("SPIDER AIM on-device mode recognition",
                    width, height, densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    reader?.surface, null, worker)
                if (display == null) {
                    stopCapture("CAPTURE_SURFACE_UNAVAILABLE")
                    return@post
                }
                display?.surface = null
                CaptureEvents.started(requireNotNull(session))
                worker.post(foregroundPoll)
                worker.post(sampleTick)
            } catch (_: Exception) {
                stopCapture("CAPTURE_START_FAILED")
            }
        }
        // A killed process never reuses its single-use projection consent token.
        return START_NOT_STICKY
    }

    private fun scaledSize(originalWidth: Int, originalHeight: Int): Pair<Int, Int> {
        val scale = minOf(1.0, LONG_EDGE_PX.toDouble() / maxOf(originalWidth, originalHeight))
        return Pair(maxOf(1, (originalWidth * scale).roundToInt()), maxOf(1, (originalHeight * scale).roundToInt()))
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Android 23–33 have no onCapturedContentResize callback. PUBG normally
        // switches from the coach's portrait UI to landscape after capture starts.
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        if (!destroyed && !competitiveSuspended) worker.post {
            if (!destroyed && !competitiveSuspended) {
                densityDpi = metrics.densityDpi
                resize(metrics.widthPixels, metrics.heightPixels)
            }
        }
    }

    private fun newReader(w: Int, h: Int): ImageReader =
        ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2).also { imageReader ->
            imageReader.setOnImageAvailableListener({ source ->
                val image = try { source.acquireLatestImage() } catch (_: Exception) { null }
                if (image != null) try { onImage(image) } finally { image.close() }
            }, worker)
        }

    private fun resize(originalWidth: Int, originalHeight: Int) {
        val size = scaledSize(originalWidth, originalHeight)
        if (size.first == width && size.second == height) return
        try {
            val old = reader
            width = size.first
            height = size.second
            reader = newReader(width, height)
            display?.resize(width, height, densityDpi)
            display?.surface = reader?.surface
            old?.setOnImageAvailableListener(null, null)
            old?.close()
            previousFingerprint = null
            previousRespawn = false
            emitUnavailable("CAPTURE_GEOMETRY_CHANGED")
        } catch (_: Exception) { stopCapture("CAPTURE_RESIZE_FAILED") }
    }

    private fun onImage(image: Image) {
        val elapsed = SystemClock.elapsedRealtime()
        if (destroyed || competitiveSuspended || processing || elapsed - lastSampleElapsed < SAMPLE_INTERVAL_MS) return
        display?.surface = null
        lastSampleElapsed = elapsed
        if (!capturedContentVisible) {
            emitUnavailable("CAPTURE_CONTENT_NOT_VISIBLE")
            return
        }
        val state = foreground.read()
        if (!state.verified) {
            previousRespawn = false
            previousFingerprint = null
            emitUnavailable(state.reason ?: "PUBG_NOT_VERIFIED_FOREGROUND", state)
            return
        }
        if (thermalTooHigh()) {
            stopCapture("THERMAL_SEVERE")
            return
        }
        if (image.width <= image.height) {
            emitUnavailable("LANDSCAPE_PUBG_SCREEN_REQUIRED", state)
            return
        }
        var bitmap: Bitmap? = null
        try {
            val plane = image.planes.first()
            val buffer = plane.buffer
            val paddedWidth = plane.rowStride / plane.pixelStride
            val padded = Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888)
            buffer.rewind()
            padded.copyPixelsFromBuffer(buffer)
            bitmap = if (paddedWidth == image.width) padded else {
                Bitmap.createBitmap(padded, 0, 0, image.width, image.height).also { padded.recycle() }
            }
            val frameBitmap = requireNotNull(bitmap)
            val fingerprint = fingerprint(frameBitmap)
            if (fingerprint == previousFingerprint) {
                frameBitmap.recycle()
                return
            }
            previousFingerprint = fingerprint
            processing = true
            val timestamp = System.currentTimeMillis()
            val sessionAtStart = session
            recognizer.process(InputImage.fromBitmap(frameBitmap, 0))
                .addOnSuccessListener(workerExecutor) { text ->
                    if (destroyed || sessionAtStart != session) return@addOnSuccessListener
                    if (!capturedContentVisible) {
                        emitUnavailable("CAPTURE_CONTENT_NOT_VISIBLE")
                        return@addOnSuccessListener
                    }
                    val verifiedAtCompletion = foreground.read()
                    if (!verifiedAtCompletion.verified || verifiedAtCompletion.packageName != state.packageName) {
                        emitUnavailable("FOREGROUND_CHANGED_DURING_OCR", verifiedAtCompletion)
                        return@addOnSuccessListener
                    }
                    val words = text.textBlocks.flatMap { block -> block.lines.flatMap { line ->
                        line.elements.mapNotNull { element ->
                            val bounds = element.boundingBox ?: return@mapNotNull null
                            // Real ML Kit confidence only; zero/unknown produces no trusted cue.
                            val confidence = element.confidence
                            OcrWord(element.text, confidence, bounds.left.toFloat() / frameBitmap.width,
                                bounds.top.toFloat() / frameBitmap.height, bounds.right.toFloat() / frameBitmap.width,
                                bounds.bottom.toFloat() / frameBitmap.height)
                        }
                    } }
                    val cues = PubgCueExtractor.extract(words, previousRespawn)
                    previousRespawn = cues.any { it.id == "respawn_countdown" }
                    val id = sessionAtStart ?: return@addOnSuccessListener
                    CaptureEvents.emit(mapOf("type" to "frame", "sessionId" to id,
                        "sequence" to ++sequence, "timestampMs" to timestamp,
                        "captureAuthorized" to true, "foregroundPackage" to state.packageName,
                        "foregroundVerified" to true, "frameFingerprint" to fingerprint,
                        "cues" to cues.map { it.toMap() }))
                    if (cues.any { it.id in COMPETITIVE_CUES && it.confidence >= 0.80 }) {
                        // Deliver blocking evidence first, then release the pixel pipeline.
                        // This session cannot resume: explicit stop and fresh user consent
                        // are necessary. The Dart guard retains its competitive latch.
                        suspendForCompetitive()
                    }
                }
                .addOnFailureListener(workerExecutor) {
                    if (!destroyed) emitUnavailable("LOCAL_OCR_FAILED")
                }
                .addOnCompleteListener(workerExecutor) {
                    // Release pixels even after consent is revoked while OCR is in flight.
                    frameBitmap.recycle()
                    processing = false
                }
        } catch (_: Exception) {
            bitmap?.takeUnless { it.isRecycled }?.recycle()
            processing = false
            emitUnavailable("CAPTURE_FRAME_UNAVAILABLE", state)
        }
    }

    /** Pixel-derived checksum: no sequence/time values, so frozen frames never add samples. */
    private fun fingerprint(bitmap: Bitmap): String {
        var hash = -3750763034362895579L
        // Sample a fixed grid with several offsets to include scene and HUD changes.
        for (y in 0 until bitmap.height step 11) for (x in 0 until bitmap.width step 13) {
            hash = (hash xor bitmap.getPixel(x, y).toLong()) * 1099511628211L
        }
        return java.lang.Long.toUnsignedString(hash, 16)
    }

    private fun emitUnavailable(reason: String, state: ForegroundEvidence? = null) {
        val id = session ?: return
        CaptureEvents.emit(mapOf("type" to "frame", "sessionId" to id,
            "sequence" to ++sequence, "timestampMs" to System.currentTimeMillis(),
            "captureAuthorized" to !destroyed, "foregroundPackage" to state?.packageName,
            "foregroundVerified" to false, "frameFingerprint" to null,
            "cues" to emptyList<Map<String, Any>>(), "reason" to reason))
    }

    private fun thermalTooHigh(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
        power.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE

    private fun suspendForCompetitive() {
        competitiveSuspended = true
        worker.removeCallbacks(foregroundPoll)
        worker.removeCallbacks(sampleTick)
        reader?.setOnImageAvailableListener(null, null)
        display?.surface = null
        display?.release()
        display = null
        reader?.close()
        reader = null
        recognizer.close()
        previousRespawn = false
        previousFingerprint = null
    }

    private fun createNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                "التعرف المحلي على وضع اللعبة", NotificationManager.IMPORTANCE_LOW))
        }
        val stop = PendingIntent.getService(this, 0, Intent(this, PubgCaptureService::class.java)
            .setAction(ACTION_STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 1,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("SPIDER AIM — تحليل الشاشة المحلي")
            .setContentText("التقاط مصرح به؛ أوقفه من هنا في أي وقت")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "إيقاف", stop).build()).build()
    }

    @Synchronized private fun stopCapture(reason: String) {
        if (destroyed) return
        destroyed = true
        worker.removeCallbacksAndMessages(null)
        reader?.setOnImageAvailableListener(null, null)
        display?.release()
        display = null
        reader?.close()
        reader = null
        projection?.unregisterCallback(projectionCallback)
        projection?.stop()
        projection = null
        recognizer.close()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalListener?.let { power.removeThermalStatusListener(it) }
        }
        thermalListener = null
        CaptureEvents.stopped(session, reason)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        if (!destroyed) stopCapture("CAPTURE_SERVICE_DESTROYED")
        // In-flight OCR callbacks use an executor that still recycles their bitmap.
        workerThread.quitSafely()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        worker.post { stopCapture("APP_TASK_REMOVED") }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
