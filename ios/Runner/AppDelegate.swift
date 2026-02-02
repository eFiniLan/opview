import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // wake lock: toggle idle timer via platform channel
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "org.dragonpilot.scope/wake_lock",
      binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { (call, result) in
      if call.method == "setKeepScreenOn" {
        let enabled = (call.arguments as? Bool) ?? true
        UIApplication.shared.isIdleTimerDisabled = enabled
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // start with screen on (matches Android FLAG_KEEP_SCREEN_ON in onCreate)
    UIApplication.shared.isIdleTimerDisabled = true

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
