import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ApnsTokenChannel.shared.attach(to: engineBridge.applicationRegistrar.messenger())
    EffectHaptics.shared.attach(to: engineBridge.applicationRegistrar.messenger())
    DataDetectors.shared.attach(to: engineBridge.applicationRegistrar.messenger())

    // From https://pub.dev/packages/flutter_local_notifications#-ios-setup
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    ApnsTokenChannel.shared.didRegister(deviceToken: deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    ApnsTokenChannel.shared.didFail(error: error)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
