import Flutter
import UIKit
import workmanager_apple
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Yeni UIScene yaşam döngüsünde firebase_messaging'in otomatik APNs token
    // yakalaması (swizzling) güvenilir çalışmıyor → APNs token Messaging'e hiç
    // ulaşmıyordu (apns=null). Kaydı açıkça tetikle + token'ı aşağıda elle ilet.
    application.registerForRemoteNotifications()
    // Arka plan sync görevi (BGTaskScheduler) — kimlik Info.plist
    // BGTaskSchedulerPermittedIdentifiers + Dart bgSyncTaskId ile birebir aynı.
    // Plugin registrant callback: arka plan isolate'ta eklentiler (secure_storage,
    // dio yok-plugin, sqlite ffi) kaydedilebilsin.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.adenababy.bgSync",
      frequency: NSNumber(value: 30 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Live Activity (süren sayaç) MethodChannel'ı implicit engine messenger'ına bağla.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AdenaLiveActivity") {
      LiveActivityBridge.register(messenger: registrar.messenger())
    }
  }

  // APNs device token → Firebase Messaging'e ELLE ilet (Scene lifecycle'da
  // swizzling yakalamadığı için kritik). Bunun ardından getToken() FCM token döner.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs kayıt HATASI: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
