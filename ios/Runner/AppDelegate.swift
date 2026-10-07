import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "spider_aim/device", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          guard call.method == "read" else {
            result(FlutterMethodNotImplemented)
            return
          }
          result(Self.readDevice())
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func readDevice() -> [String: Any] {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let screen = UIScreen.main
    let process = ProcessInfo.processInfo
    let preferences = UserDefaults.standard
    let installationId: String
    if let stored = preferences.string(forKey: "spiderAimInstallationId") {
      installationId = stored
    } else {
      installationId = UUID().uuidString
      preferences.set(installationId, forKey: "spiderAimInstallationId")
    }

    #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
    let physicalDevice = false
    #else
    let physicalDevice: Bool
    if #available(iOS 14.0, *) {
      physicalDevice = !process.isiOSAppOnMac
    } else {
      physicalDevice = true
    }
    #endif
    let mobile = device.userInterfaceIdiom == .phone || device.userInterfaceIdiom == .pad

    var systemInfo = utsname()
    uname(&systemInfo)
    let modelBufferSize = MemoryLayout.size(ofValue: systemInfo.machine)
    let hardwareModel = withUnsafePointer(to: &systemInfo.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: modelBufferSize) { String(cString: $0) }
    }
    let thermal: String
    switch process.thermalState {
    case .nominal: thermal = "NOMINAL"
    case .fair: thermal = "MODERATE"
    case .serious: thermal = "SEVERE"
    case .critical: thermal = "CRITICAL"
    @unknown default: thermal = "UNKNOWN"
    }
    let charging: Any
    switch device.batteryState {
    case .charging, .full: charging = true
    case .unplugged: charging = false
    case .unknown: charging = NSNull()
    @unknown default: charging = NSNull()
    }

    // No motion updates are started. This query reports capability only.
    let motion = CMMotionManager()
    let batteryPercent: Any
    if device.batteryLevel < 0 {
      batteryPercent = NSNull()
    } else {
      batteryPercent = Double(device.batteryLevel) * 100.0
    }
    return [
      "deviceId": installationId,
      "capturedAtUnixMs": Int64(Date().timeIntervalSince1970 * 1000.0),
      "name": "Apple \(hardwareModel)",
      "manufacturer": "Apple",
      "model": hardwareModel,
      "platform": "ios",
      "osVersion": device.systemVersion,
      "physicalDevice": physicalDevice,
      "physicalDeviceDetection": "SIMULATOR_CATALYST_AND_IOS_ON_MAC_EXCLUDED",
      "supported": physicalDevice && mobile,
      "formFactor": device.userInterfaceIdiom == .pad ? "tablet" : "phone",
      "screenWidthPx": Int(screen.nativeBounds.width),
      "screenHeightPx": Int(screen.nativeBounds.height),
      "logicalWidth": Double(screen.bounds.width),
      "logicalHeight": Double(screen.bounds.height),
      "pixelDensityScale": Double(screen.scale),
      "nativeScale": Double(screen.nativeScale),
      "densityDpi": NSNull(),
      "physicalScreenSizeInches": NSNull(),
      "maximumRefreshRateHz": screen.maximumFramesPerSecond,
      // maximumFramesPerSecond is a maximum, not a measured active refresh rate.
      "availableRefreshRatesHz": NSNull(),
      "reportedRefreshRateHz": NSNull(),
      "pubgFps": NSNull(),
      "touchSamplingRateHz": NSNull(),
      "touchSamplingStatus": "UNKNOWN",
      // UIKit does not publish a hardware maximum-contact capability query.
      "multitouch": NSNull(),
      "gyroscopeAvailable": motion.isGyroAvailable,
      "gyroscopeEnabled": false,
      "batteryPercent": batteryPercent,
      "charging": charging,
      "batteryTemperatureCelsius": NSNull(),
      "thermal": thermal,
      "lowPowerMode": process.isLowPowerModeEnabled,
      "totalMemoryBytes": process.physicalMemory,
      "availableMemoryBytes": NSNull(),
      "availableProcessorCount": process.activeProcessorCount,
      "deviceUptimeMs": process.systemUptime * 1000.0,
      "appCpuTimeMs": NSNull(),
      "appPssKb": NSNull(),
      "pubgBatteryConsumption": NSNull(),
      "gpuUtilizationPercent": NSNull(),
      "cpuTemperatureCelsius": NSNull(),
      "screenCaptureAvailable": false,
      "gameModeDetectionAvailable": false,
    ]
  }
}
