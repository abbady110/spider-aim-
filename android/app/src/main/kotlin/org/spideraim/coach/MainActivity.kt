package org.spideraim.coach

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
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
            "screenCaptureAvailable" to false,
            "gameModeDetectionAvailable" to false
        )
    }
}
