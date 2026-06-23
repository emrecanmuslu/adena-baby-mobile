import Flutter
import UIKit
import UserNotifications
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

  // GELEN MESAJ köprüsü — APNs token'ında olduğu gibi, yeni UIScene yaşam
  // döngüsünde firebase_messaging'in swizzling'i gelen bildirim callback'lerini
  // güvenilir yakalayamıyor → mesajı Messaging'e ELLE iletiyoruz. Aksi halde
  // ön planda onMessage hiç ateşlenmez (sync tetiklenmez) ve arka planda
  // data/silent push işlenmez (widget güncellenmez).

  // Ön plan: bildirim geldiğinde FlutterFire'a ilet (onMessage ateşlensin) +
  // banner'ı göster (super, Dart setForegroundNotificationPresentationOptions'a göre karar verir).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
    super.userNotificationCenter(
      center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  // Data / silent push (ön plan + arka plan): Messaging'e ilet → onMessage /
  // onBackgroundMessage ateşlensin (widget güncellemesi, sessiz sync).
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    Messaging.messaging().appDidReceiveMessage(userInfo)
    super.application(
      application, didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler)
  }
}
