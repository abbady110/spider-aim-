package org.spideraim.coach

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.projection.MediaProjectionManager
import android.media.projection.MediaProjectionConfig
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import org.spideraim.coach.capture.CaptureEvents
import org.spideraim.coach.capture.PubgCaptureService
import org.spideraim.coach.capture.PubgForegroundVerifier
import org.spideraim.coach.overlay.CalibrationOverlay
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var captureResult: MethodChannel.Result? = null
    private var pendingSession: String? = null
    private var overlay: CalibrationOverlay? = null
    private var overlayChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spider_aim/device")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                } else {
                    try {
                        result.success(readDevice())
                    } catch (error: Exception) {
                        result.error("DEVICE_REPORT_UNAVAILABLE", "Public platform report unavailable", null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spider_aim/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> result.success(captureCapabilities())
                    "status" -> result.success(CaptureEvents.status())
                    "requestUsageAccess" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS,
                                Uri.parse("package:$packageName")))
                            result.success(mapOf("opened" to true,
                                "usageAccessGranted" to PubgForegroundVerifier.hasUsageAccess(this)))
                        } catch (_: Exception) {
                            result.success(mapOf("opened" to false, "usageAccessGranted" to false,
                                "reason" to "USAGE_SETTINGS_UNAVAILABLE"))
                        }
                    }
                    "start" -> startCapture(result)
                    "stop" -> {
                        pendingSession?.let { CaptureEvents.stopped(it, "STOPPED_BY_USER") }
                        captureResult?.success(mapOf("supported" to true, "started" to false,
                            "sessionId" to pendingSession, "reason" to "STOPPED_BY_USER"))
                        captureResult = null
                        pendingSession = null
                        CaptureEvents.startListener = null
                        if (CaptureEvents.running) {
                            startService(Intent(this, PubgCaptureService::class.java)
                                .setAction(PubgCaptureService.ACTION_STOP))
                        }
                        result.success(mapOf("stopped" to true))
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "spider_aim/capture/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    CaptureEvents.sink = events
                    // Status only; never replay an earlier safe frame or its evidence.
                    events.success(CaptureEvents.status() + mapOf("type" to "status",
                        "timestampMs" to System.currentTimeMillis()))
                }
                override fun onCancel(arguments: Any?) {
                    CaptureEvents.sink = null
                    if (CaptureEvents.running) {
                        startService(Intent(applicationContext, PubgCaptureService::class.java)
                            .setAction(PubgCaptureService.ACTION_STOP))
                    }
                }
            })
        val overlayMethods = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spider_aim/overlay")
        overlayChannel = overlayMethods
        overlay?.destroy()
        overlay = CalibrationOverlay(this, overlayMethods)
        overlayMethods.setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(mapOf(
                    "supported" to (try { readDevice()["supported"] == true } catch (_: Exception) { false }),
                    "permissionGranted" to Settings.canDrawOverlays(this)))
                "requestPermission" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        result.success(mapOf("opened" to true,
                            "permissionGranted" to Settings.canDrawOverlays(this)))
                    } catch (_: Exception) {
                        result.success(mapOf("opened" to false, "permissionGranted" to false,
                            "reason" to "OVERLAY_SETTINGS_UNAVAILABLE"))
                    }
                }
                "show" -> {
                    if (try { readDevice()["supported"] != true } catch (_: Exception) { true }) {
                        result.success(mapOf("visible" to false, "reason" to "UNSUPPORTED_DEVICE"))
                    } else result.success(overlay?.show() ?: mapOf("visible" to false))
                }
                "hide" -> result.success(overlay?.hide() ?: mapOf("visible" to false))
                "updateState" -> {
                    @Suppress("UNCHECKED_CAST")
                    val state = call.arguments as? Map<String, Any?> ?: emptyMap()
                    overlay?.updateState(state)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        overlay?.onDisplayChanged()
    }

    override fun onDestroy() {
        overlay?.destroy()
        overlay = null
        overlayChannel?.setMethodCallHandler(null)
        overlayChannel = null
        super.onDestroy()
    }

    private fun captureCapabilities(): Map<String, Any?> {
        val supported = try { readDevice()["supported"] == true } catch (_: Exception) { false }
        return mapOf("supported" to supported, "platform" to "android",
            "captureApi" to "MediaProjection", "requiresUserConsent" to true,
            "usageAccessGranted" to PubgForegroundVerifier.hasUsageAccess(this),
            "foregroundVerification" to "UsageStats", "onDeviceOcr" to true,
            "ocrScript" to "LATIN_ONLY", "sampleIntervalMs" to 2000,
            "longEdgePx" to 960,
            "notificationPermissionGranted" to (Build.VERSION.SDK_INT < 33 ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED),
            "reason" to if (supported) null else "UNSUPPORTED_DEVICE")
    }

    private fun startCapture(result: MethodChannel.Result) {
        val supported = captureCapabilities()["supported"] == true
        if (!supported) {
            result.success(mapOf("supported" to false, "started" to false, "reason" to "UNSUPPORTED_DEVICE"))
            return
        }
        if (CaptureEvents.running) {
            result.success(CaptureEvents.status())
            return
        }
        if (captureResult != null) {
            result.success(mapOf("supported" to true, "started" to false, "reason" to "CONSENT_ALREADY_PENDING"))
            return
        }
        if (!PubgForegroundVerifier.hasUsageAccess(this)) {
            result.success(mapOf("supported" to true, "started" to false, "reason" to "USAGE_ACCESS_REQUIRED"))
            return
        }
        captureResult = result
        pendingSession = UUID.randomUUID().toString()
        CaptureEvents.prepare(requireNotNull(pendingSession))
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
        } else beginProjectionConsent()
    }

    private fun beginProjectionConsent() {
        if (captureResult == null) return
        try {
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            @Suppress("DEPRECATION")
            val consent = if (Build.VERSION.SDK_INT >= 34) {
                // Require the actual display, not a different app's selected window.
                manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
            } else manager.createScreenCaptureIntent()
            startActivityForResult(consent, CAPTURE_REQUEST)
        } catch (_: Exception) {
            finishCaptureStart("CAPTURE_CONSENT_UNAVAILABLE")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) {
            // A denied optional notification permission does not imply screen consent.
            // Android still exposes the foreground capture in its active-apps manager.
            beginProjectionConsent()
        }
    }

    @Deprecated("Official MediaProjection result bridge for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_REQUEST || captureResult == null) return
        if (resultCode != RESULT_OK || data == null) {
            finishCaptureStart("CAPTURE_CONSENT_DENIED")
            return
        }
        val id = pendingSession ?: return
        CaptureEvents.startListener = { status ->
            captureResult?.success(status)
            captureResult = null
            pendingSession = null
        }
        val intent = Intent(this, PubgCaptureService::class.java)
            .setAction(PubgCaptureService.ACTION_START)
            .putExtra(PubgCaptureService.EXTRA_SESSION, id)
            .putExtra(PubgCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(PubgCaptureService.EXTRA_PROJECTION_DATA, data)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
            else startService(intent)
        } catch (_: Exception) { finishCaptureStart("FOREGROUND_SERVICE_START_DENIED") }
    }

    private fun finishCaptureStart(reason: String) {
        CaptureEvents.startListener = null
        captureResult?.success(mapOf("supported" to true, "started" to false,
            "sessionId" to pendingSession, "reason" to reason))
        CaptureEvents.stopped(pendingSession, reason)
        captureResult = null
        pendingSession = null
    }

    companion object {
        private const val CAPTURE_REQUEST = 4822
        private const val NOTIFICATION_REQUEST = 4823
    }

    @Suppress("DEPRECATION")
    private fun readDevice(): Map<String, Any?> {
        val preferences = getSharedPreferences("spider_aim_device", Context.MODE_PRIVATE)
        val installationId = preferences.getString("installationId", null)
            ?: UUID.randomUUID().toString().also {
                check(preferences.edit().putString("installationId", it).commit())
            }
        val features = applicationContext.packageManager
        val formFactorSupported = features.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) &&
            !features.hasSystemFeature(PackageManager.FEATURE_TELEVISION) &&
            !features.hasSystemFeature(PackageManager.FEATURE_LEANBACK) &&
            !features.hasSystemFeature(PackageManager.FEATURE_WATCH) &&
            !features.hasSystemFeature("android.hardware.type.automotive") &&
            !features.hasSystemFeature("android.hardware.type.pc")

        // Android exposes no authoritative public physical-device attestation API.
        // Common emulator signatures are blocked. This is a documented heuristic,
        // not a guarantee against spoofed device properties or all emulators.
        val suspectedEmulator = Build.FINGERPRINT.startsWith("generic") ||
            Build.FINGERPRINT.startsWith("unknown") || Build.MODEL.contains("google_sdk") ||
            Build.MODEL.contains("Emulator") || Build.MODEL.contains("Android SDK built for") ||
            Build.MANUFACTURER.contains("Genymotion") || Build.HARDWARE.contains("goldfish") ||
            Build.HARDWARE.contains("ranchu") || Build.PRODUCT.contains("sdk") ||
            Build.PRODUCT.contains("vbox") || Build.PRODUCT.contains("emulator") ||
            (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")) ||
            Build.SUPPORTED_ABIS.none { it == "arm64-v8a" || it == "armeabi-v7a" }
        val knownIdentity = Build.MODEL.isNotBlank() && Build.MODEL != Build.UNKNOWN &&
            Build.MANUFACTURER.isNotBlank() && Build.MANUFACTURER != Build.UNKNOWN

        val display = windowManager.defaultDisplay
        val metrics = DisplayMetrics().also { display.getRealMetrics(it) }
        val logicalMetrics = resources.displayMetrics
        val memory = ActivityManager.MemoryInfo().also {
            (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(it)
        }
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val batteryTemperature = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (power.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE -> "NOMINAL"
                PowerManager.THERMAL_STATUS_LIGHT -> "LIGHT"
                PowerManager.THERMAL_STATUS_MODERATE -> "MODERATE"
                PowerManager.THERMAL_STATUS_SEVERE -> "SEVERE"
                PowerManager.THERMAL_STATUS_CRITICAL -> "CRITICAL"
                PowerManager.THERMAL_STATUS_EMERGENCY -> "EMERGENCY"
                PowerManager.THERMAL_STATUS_SHUTDOWN -> "SHUTDOWN"
                else -> "UNKNOWN"
            }
        } else "UNKNOWN"

        return mapOf(
            "deviceId" to installationId,
            "capturedAtUnixMs" to System.currentTimeMillis(),
            "name" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "platform" to "android",
            "osVersion" to Build.VERSION.RELEASE,
            "sdkVersion" to Build.VERSION.SDK_INT,
            "physicalDevice" to (knownIdentity && !suspectedEmulator),
            "physicalDeviceDetection" to "ANDROID_BUILD_HEURISTIC_NOT_ATTESTATION",
            "supported" to (formFactorSupported && knownIdentity && !suspectedEmulator),
            "formFactor" to if (resources.configuration.smallestScreenWidthDp >= 600) "tablet" else "phone",
            "screenWidthPx" to metrics.widthPixels,
            "screenHeightPx" to metrics.heightPixels,
            "logicalWidth" to logicalMetrics.widthPixels / logicalMetrics.density,
            "logicalHeight" to logicalMetrics.heightPixels / logicalMetrics.density,
            "pixelDensityScale" to metrics.density,
            "densityDpi" to metrics.densityDpi,
            "reportedXdpi" to metrics.xdpi,
            "reportedYdpi" to metrics.ydpi,
            "physicalScreenSizeInches" to null,
            "availableRefreshRatesHz" to display.supportedModes.map { it.refreshRate.toDouble() }.distinct().sorted(),
            "reportedRefreshRateHz" to display.refreshRate.toDouble(),
            "pubgFps" to null,
            "touchSamplingRateHz" to null,
            "touchSamplingStatus" to "UNKNOWN",
            "multitouch" to features.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN_MULTITOUCH),
            "multitouchDistinct" to features.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN_MULTITOUCH_DISTINCT),
            "gyroscopeAvailable" to features.hasSystemFeature(PackageManager.FEATURE_SENSOR_GYROSCOPE),
            "gyroscopeEnabled" to false,
            "batteryPercent" to if (level >= 0 && scale > 0) level * 100.0 / scale else null,
            "charging" to if (status < 0 || status == BatteryManager.BATTERY_STATUS_UNKNOWN) null else
                (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "batteryTemperatureCelsius" to if (batteryTemperature != null && batteryTemperature != Int.MIN_VALUE)
                batteryTemperature / 10.0 else null,
            "thermal" to thermal,
            "lowPowerMode" to power.isPowerSaveMode,
            "totalMemoryBytes" to memory.totalMem,
            "availableMemoryBytes" to memory.availMem,
            "availableProcessorCount" to Runtime.getRuntime().availableProcessors(),
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "appCpuTimeMs" to android.os.Process.getElapsedCpuTime(),
            "deviceUptimeMs" to SystemClock.elapsedRealtime(),
            "appPssKb" to Debug.getPss(),
            "pubgBatteryConsumption" to null,
            "gpuUtilizationPercent" to null,
            "cpuTemperatureCelsius" to null,
            "screenCaptureAvailable" to (formFactorSupported && knownIdentity && !suspectedEmulator),
            "gameModeDetectionAvailable" to (formFactorSupported && knownIdentity && !suspectedEmulator)
        )
    }
}
