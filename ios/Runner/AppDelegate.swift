import Flutter
import UIKit
import UserNotifications
import LocalAuthentication
import Network

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var alarmChannel: FlutterMethodChannel?
  private var permissionsChannel: FlutterMethodChannel?
  private var preferencesChannel: FlutterMethodChannel?
  private var biometricChannel: FlutterMethodChannel?
  private var timezoneChannel: FlutterMethodChannel?
  private var connectivityChannel: FlutterMethodChannel?
  private var shareChannel: FlutterMethodChannel?

  private let pathMonitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "daily_planner.network_monitor")
  private var currentConnectivityStatus: String = "wifi"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set notification center delegate
    UNUserNotificationCenter.current().delegate = self

    // Register notification categories (Stop, Snooze)
    setupNotificationCategories()

    // Register for remote notifications safely on main thread
    application.registerForRemoteNotifications()

    // Setup network connectivity monitoring
    startNetworkMonitoring()

    // Setup Flutter method channels
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    setupMethodChannels(controller: controller)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Notification Categories Setup

  private func setupNotificationCategories() {
    let stopAction = UNNotificationAction(
      identifier: "stop_action",
      title: "Dismiss",
      options: [.destructive]
    )

    let snoozeAction = UNNotificationAction(
      identifier: "snooze_action",
      title: "Snooze 5m",
      options: []  // No .foreground: snooze happens in background, doesn't force-open the app
    )

    let alarmCategory = UNNotificationCategory(
      identifier: "DAILY_PLANNER_ALARM",
      actions: [stopAction, snoozeAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )

    UNUserNotificationCenter.current().setNotificationCategories([alarmCategory])
  }

  // MARK: - Foreground Notification Presentation

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show banner, badge, and sound when app is in foreground on iOS 14+ / iOS 15+ / iOS 16+
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound, .list])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  // MARK: - Notification Tap & Action Response

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let id = (userInfo["id"] as? NSNumber)?.intValue
      ?? (userInfo["id"] as? Int)
      ?? (Int(response.notification.request.identifier.replacingOccurrences(of: "alarm_", with: "")) ?? 0)
    let title = response.notification.request.content.title
    let body = response.notification.request.content.body
    let payload = userInfo["payload"] as? String

    var action = "tap"
    if response.actionIdentifier == "stop_action" {
      action = "stop"
    } else if response.actionIdentifier == "snooze_action" {
      action = "snooze"
    } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
      action = "dismiss"
    }

    // Forward action to Flutter on the main queue
    DispatchQueue.main.async { [weak self] in
      self?.alarmChannel?.invokeMethod("onNotificationAction", arguments: [
        "action": action,
        "id": id,
        "title": title,
        "body": body,
        "payload": payload ?? ""
      ])
    }

    completionHandler()
  }

  // MARK: - Method Channels Setup

  private func setupMethodChannels(controller: FlutterViewController) {
    let messenger = controller.binaryMessenger

    // 1. Alarm & Service Channels
    alarmChannel = FlutterMethodChannel(name: "com.example.daily_planner/alarm", binaryMessenger: messenger)
    let exactAlarmChannel = FlutterMethodChannel(name: "exact_alarm_permission", binaryMessenger: messenger)
    let serviceChannel = FlutterMethodChannel(name: "daily_planner/alarm_service", binaryMessenger: messenger)

    let alarmHandler: FlutterMethodCallHandler = { [weak self] call, result in
      self?.handleAlarmCalls(call: call, result: result)
    }

    alarmChannel?.setMethodCallHandler(alarmHandler)
    exactAlarmChannel.setMethodCallHandler(alarmHandler)
    serviceChannel.setMethodCallHandler(alarmHandler)

    // 2. Permissions Channel
    permissionsChannel = FlutterMethodChannel(name: "daily_planner/native_permissions", binaryMessenger: messenger)
    permissionsChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handlePermissionCalls(call: call, result: result)
    }

    // 3. Preferences Channel
    preferencesChannel = FlutterMethodChannel(name: "daily_planner/native_preferences", binaryMessenger: messenger)
    preferencesChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handlePreferencesCalls(call: call, result: result)
    }

    // 4. Biometric Channel
    biometricChannel = FlutterMethodChannel(name: "daily_planner/native_biometric", binaryMessenger: messenger)
    biometricChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleBiometricCalls(call: call, result: result)
    }

    // 5. Timezone Channel
    timezoneChannel = FlutterMethodChannel(name: "daily_planner/native_timezone", binaryMessenger: messenger)
    timezoneChannel?.setMethodCallHandler { call, result in
      if call.method == "getDeviceTimezone" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // 6. Connectivity Channel
    connectivityChannel = FlutterMethodChannel(name: "daily_planner/native_connectivity", binaryMessenger: messenger)
    connectivityChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "checkConnectivity" {
        result(self?.currentConnectivityStatus ?? "wifi")
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // 7. Share Channel
    shareChannel = FlutterMethodChannel(name: "daily_planner/native_share", binaryMessenger: messenger)
    shareChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "shareText" {
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        let subject = args?["subject"] as? String
        self?.shareText(text: text, subject: subject, controller: controller, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Alarm & Notification Handler (Crash-Resistant for iOS)

  private func handleAlarmCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scheduleNativeAlarm", "scheduleAlarm":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a Map", details: nil))
        return
      }

      let rawId = (args["id"] as? NSNumber)?.intValue ?? 0
      let id = rawId != 0 ? abs(rawId) : Int(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100000)) + 1
      let title = args["title"] as? String ?? "Daily Planner"
      let body = args["body"] as? String ?? "You have a scheduled task"
      let timeInMillis = (args["time"] as? NSNumber)?.int64Value
        ?? (args["timeInMillis"] as? NSNumber)?.int64Value
        ?? 0
      let payload = args["payload"] as? String ?? ""

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      content.categoryIdentifier = "DAILY_PLANNER_ALARM"
      if #available(iOS 15.0, *) {
        content.interruptionLevel = .timeSensitive
      }
      content.userInfo = [
        "id": NSNumber(value: id),
        "title": title,
        "body": body,
        "payload": payload,
        "timeInMillis": NSNumber(value: timeInMillis)
      ]

      let trigger: UNNotificationTrigger?
      if timeInMillis > 0 {
        let targetDate = Date(timeIntervalSince1970: Double(timeInMillis) / 1000.0)
        let timeInterval = targetDate.timeIntervalSinceNow
        if timeInterval > 1.0 {
          let calendar = Calendar.current
          let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: targetDate)
          trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
          // Immediately deliver using trigger: nil (prevents UNTimeIntervalNotificationTrigger crash on <= 0)
          trigger = nil
        }
      } else {
        trigger = nil
      }

      let request = UNNotificationRequest(identifier: "alarm_\(id)", content: content, trigger: trigger)

      UNUserNotificationCenter.current().add(request) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "SCHEDULING_ERROR", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        }
      }

    case "showNotification", "showNow":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a Map", details: nil))
        return
      }

      let rawId = (args["id"] as? NSNumber)?.intValue ?? 0
      let id = rawId != 0 ? abs(rawId) : Int(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100000)) + 1
      let title = args["title"] as? String ?? "Daily Planner"
      let body = args["body"] as? String ?? "Notification"
      let payload = args["payload"] as? String ?? ""

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      content.categoryIdentifier = "DAILY_PLANNER_ALARM"
      if #available(iOS 15.0, *) {
        content.interruptionLevel = .timeSensitive
      }
      content.userInfo = [
        "id": NSNumber(value: id),
        "title": title,
        "body": body,
        "payload": payload
      ]

      // trigger: nil delivers immediately on iOS without crashing
      let request = UNNotificationRequest(identifier: "alarm_\(id)", content: content, trigger: nil)

      UNUserNotificationCenter.current().add(request) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "NOTIFICATION_ERROR", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        }
      }

    case "cancelAlarm", "cancelNativeAlarm":
      let id: Int?
      if let args = call.arguments as? [String: Any], let rawId = (args["id"] as? NSNumber)?.intValue {
        id = rawId
      } else if let num = (call.arguments as? NSNumber)?.intValue {
        id = num
      } else {
        id = nil
      }

      if let id = id {
        let identifiers = ["alarm_\(id)", "\(id)"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
      }
      result(true)

    case "cancelAllAlarms":
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      result(true)

    case "getScheduledAlarms":
      UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
        var alarms: [[String: Any]] = []
        for req in requests {
          let userInfo = req.content.userInfo
          let id = (userInfo["id"] as? NSNumber)?.intValue
            ?? (userInfo["id"] as? Int)
            ?? (Int(req.identifier.replacingOccurrences(of: "alarm_", with: "")) ?? 0)
          let timeInMillis = (userInfo["timeInMillis"] as? NSNumber)?.int64Value
            ?? (userInfo["timeInMillis"] as? Int64)
            ?? 0
          let payload = (userInfo["payload"] as? String) ?? ""

          alarms.append([
            "id": id,
            "title": req.content.title,
            "body": req.content.body,
            "timeInMillis": timeInMillis,
            "payload": payload
          ])
        }

        DispatchQueue.main.async {
          result(alarms)
        }
      }

    case "ensureNotificationChannel":
      setupNotificationCategories()
      result(true)

    case "checkExactAlarmPermission", "canScheduleExactAlarms":
      result(true)

    case "requestExactAlarmPermission", "openExactAlarmSettings":
      result(true)

    case "startForegroundService", "stopForegroundService", "isServiceRunning":
      result(true)

    case "getDeviceBrandInfo":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let granted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        DispatchQueue.main.async {
          result([
            "manufacturer": "Apple",
            "brand": "Apple",
            "model": UIDevice.current.model,
            "sdkVersion": UIDevice.current.systemVersion,
            "isIgnoringBatteryOptimizations": true,
            "canScheduleExactAlarms": true,
            "isNotificationPermissionGranted": granted
          ])
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permissions Handler

  private func handlePermissionCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkNotificationPermission":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let granted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        DispatchQueue.main.async {
          result(granted)
        }
      }

    case "requestNotificationPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        DispatchQueue.main.async {
          if granted {
            UIApplication.shared.registerForRemoteNotifications()
          }
          result(granted)
        }
      }

    case "checkCriticalAlertPermission":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let granted: Bool
        if #available(iOS 12.0, *) {
          granted = (settings.criticalAlertSetting == .enabled)
        } else {
          granted = false
        }
        DispatchQueue.main.async {
          result(granted)
        }
      }

    case "requestCriticalAlertPermission":
      if #available(iOS 12.0, *) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { granted, error in
          DispatchQueue.main.async {
            result(granted)
          }
        }
      } else {
        result(false)
      }

    case "openNotificationSettings", "openAppSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { success in
          result(success)
        }
      }

    case "checkExactAlarmPermission", "isIgnoringBatteryOptimizations":
      result(true)

    case "requestExactAlarmPermission", "disableBatteryOptimization", "openAutoStartSettings":
      result(false)

    case "getAndroidSdkVersion":
      result(0)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Persistent Key-Value Preferences Handler (UserDefaults Safe Serialization)

  private func handlePreferencesCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let defaults = UserDefaults.standard
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "getAll":
      var dict: [String: Any] = [:]
      let defaultsDict = defaults.dictionaryRepresentation()
      for (key, val) in defaultsDict {
        // Filter out non-serializable objects (NSDate, NSData, internal Apple classes)
        // that cause FlutterStandardMessageCodec encoding crashes.
        if let str = val as? String {
          dict[key] = str
        } else if let boolVal = val as? Bool {
          dict[key] = boolVal
        } else if let num = val as? NSNumber {
          dict[key] = num
        } else if let strArr = val as? [String] {
          dict[key] = strArr
        }
      }
      result(dict)

    case "getString":
      if let key = args?["key"] as? String {
        result(defaults.string(forKey: key))
      } else {
        result(nil)
      }

    case "getBool":
      if let key = args?["key"] as? String {
        if defaults.object(forKey: key) != nil {
          result(defaults.bool(forKey: key))
        } else {
          result(nil)
        }
      } else {
        result(nil)
      }

    case "getInt":
      if let key = args?["key"] as? String {
        if defaults.object(forKey: key) != nil {
          result(defaults.integer(forKey: key))
        } else {
          result(nil)
        }
      } else {
        result(nil)
      }

    case "getDouble":
      if let key = args?["key"] as? String {
        if defaults.object(forKey: key) != nil {
          result(defaults.double(forKey: key))
        } else {
          result(nil)
        }
      } else {
        result(nil)
      }

    case "setBool":
      if let key = args?["key"] as? String, let val = args?["value"] as? Bool {
        defaults.set(val, forKey: key)
        defaults.synchronize()
        result(true)
      } else {
        result(false)
      }

    case "setInt":
      if let key = args?["key"] as? String, let val = args?["value"] as? NSNumber {
        defaults.set(val.intValue, forKey: key)
        defaults.synchronize()
        result(true)
      } else {
        result(false)
      }

    case "setDouble":
      if let key = args?["key"] as? String, let val = args?["value"] as? NSNumber {
        defaults.set(val.doubleValue, forKey: key)
        defaults.synchronize()
        result(true)
      } else {
        result(false)
      }

    case "setString":
      if let key = args?["key"] as? String, let val = args?["value"] as? String {
        defaults.set(val, forKey: key)
        defaults.synchronize()
        result(true)
      } else {
        result(false)
      }

    case "setStringList":
      if let key = args?["key"] as? String, let val = args?["value"] as? [String] {
        defaults.set(val, forKey: key)
        defaults.synchronize()
        result(true)
      } else {
        result(false)
      }

    case "remove":
      if let key = args?["key"] as? String {
        defaults.removeObject(forKey: key)
        defaults.synchronize()
        result(true)
      } else {
        result(false)
      }

    case "clear":
      if let domain = Bundle.main.bundleIdentifier {
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
      }
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Biometric Authentication Handler (LocalAuthentication)

  private func handleBiometricCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let context = LAContext()
    var error: NSError?

    switch call.method {
    case "isBiometricSupported":
      let canBiometric = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      let canPasscode = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
      result(canBiometric || canPasscode)

    case "canCheckBiometrics":
      let canBiometric = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      result(canBiometric)

    case "getAvailableBiometrics":
      _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      var biometrics: [String] = []
      if #available(iOS 11.0, *) {
        switch context.biometryType {
        case .faceID:
          biometrics.append("face")
        case .touchID:
          biometrics.append("fingerprint")
        case .opticID:
          biometrics.append("iris")
        default:
          break
        }
      }
      result(biometrics)

    case "authenticateBiometric":
      let args = call.arguments as? [String: Any]
      let reason = args?["title"] as? String ?? "Verify your identity to proceed"
      context.localizedCancelTitle = args?["negativeButtonText"] as? String ?? "Cancel"

      context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
        DispatchQueue.main.async {
          result(success)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Network Connectivity Monitoring (NWPathMonitor)

  private func startNetworkMonitoring() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let status: String
      if path.status == .satisfied {
        if path.usesInterfaceType(.wifi) {
          status = "wifi"
        } else if path.usesInterfaceType(.cellular) {
          status = "mobile"
        } else if path.usesInterfaceType(.wiredEthernet) {
          status = "ethernet"
        } else {
          status = "wifi"
        }
      } else {
        status = "none"
      }

      self?.currentConnectivityStatus = status
      DispatchQueue.main.async {
        self?.connectivityChannel?.invokeMethod("onConnectivityChanged", arguments: status)
      }
    }
    pathMonitor.start(queue: monitorQueue)
  }

  // MARK: - Native Share Sheet Handler

  private func shareText(text: String, subject: String?, controller: UIViewController, result: @escaping FlutterResult) {
    guard !text.isEmpty else {
      result(false)
      return
    }

    let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    if let subject = subject, !subject.isEmpty {
      activityVC.setValue(subject, forKey: "subject")
    }

    if let popover = activityVC.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }

    controller.present(activityVC, animated: true) {
      result(true)
    }
  }
}
