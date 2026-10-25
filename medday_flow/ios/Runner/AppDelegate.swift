import Flutter
import UIKit
import UserNotifications
import LocalAuthentication
import Network
import HealthKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  // 1. Create a shared Flutter Engine
  lazy var flutterEngine = FlutterEngine(name: "medday_flow_engine")

  // ✅ Track whether we've already started the engine
  private var engineStarted = false

  private var alarmChannel: FlutterMethodChannel?
  private var permissionsChannel: FlutterMethodChannel?
  private var preferencesChannel: FlutterMethodChannel?
  private var biometricChannel: FlutterMethodChannel?
  private var timezoneChannel: FlutterMethodChannel?
  private var connectivityChannel: FlutterMethodChannel?
  private var shareChannel: FlutterMethodChannel?
  private var healthChannel: FlutterMethodChannel?
  private var _healthStoreInstance: HKHealthStore?
  private let healthLock = NSLock()

  private func getHealthStore() -> HKHealthStore? {
    healthLock.lock()
    defer { healthLock.unlock() }
    if _healthStoreInstance == nil {
      var isAvail = false
      let checkException = CatchObjCException {
        isAvail = HKHealthStore.isHealthDataAvailable()
      }
      if checkException != nil || !isAvail {
        return nil
      }

      var store: HKHealthStore?
      let initException = CatchObjCException {
        store = HKHealthStore()
      }
      if let ex = initException {
        print("⚠️ HealthKit initialization exception: \(ex.name.rawValue) - \(ex.reason ?? "")")
        return nil
      }
      _healthStoreInstance = store
    }
    return _healthStoreInstance
  }

  private let pathMonitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "medday_flow.network_monitor")
  private var currentConnectivityStatus: String = "wifi"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    if engineStarted {
      print("⚠️ AppDelegate: flutterEngine already started — skipping run()")
    } else {
      print("✅ AppDelegate: starting flutterEngine for the first time")
      flutterEngine.run()
      engineStarted = true
    }

    GeneratedPluginRegistrant.register(with: flutterEngine)

    UNUserNotificationCenter.current().delegate = self
    setupNotificationCategories()
    application.registerForRemoteNotifications()
    startNetworkMonitoring()
    setupMethodChannels(messenger: flutterEngine.binaryMessenger)

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
      options: []
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

  private func setupMethodChannels(messenger: FlutterBinaryMessenger) {
    alarmChannel = FlutterMethodChannel(name: "com.example.daily_planner/alarm", binaryMessenger: messenger)
    let exactAlarmChannel = FlutterMethodChannel(name: "exact_alarm_permission", binaryMessenger: messenger)
    let serviceChannel = FlutterMethodChannel(name: "daily_planner/alarm_service", binaryMessenger: messenger)

    let alarmHandler: FlutterMethodCallHandler = { [weak self] call, result in
      self?.handleAlarmCalls(call: call, result: result)
    }

    alarmChannel?.setMethodCallHandler(alarmHandler)
    exactAlarmChannel.setMethodCallHandler(alarmHandler)
    serviceChannel.setMethodCallHandler(alarmHandler)

    permissionsChannel = FlutterMethodChannel(name: "daily_planner/native_permissions", binaryMessenger: messenger)
    permissionsChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handlePermissionCalls(call: call, result: result)
    }

    preferencesChannel = FlutterMethodChannel(name: "daily_planner/native_preferences", binaryMessenger: messenger)
    preferencesChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handlePreferencesCalls(call: call, result: result)
    }

    biometricChannel = FlutterMethodChannel(name: "daily_planner/native_biometric", binaryMessenger: messenger)
    biometricChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleBiometricCalls(call: call, result: result)
    }

    timezoneChannel = FlutterMethodChannel(name: "daily_planner/native_timezone", binaryMessenger: messenger)
    timezoneChannel?.setMethodCallHandler { call, result in
      if call.method == "getDeviceTimezone" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    connectivityChannel = FlutterMethodChannel(name: "daily_planner/native_connectivity", binaryMessenger: messenger)
    connectivityChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "checkConnectivity" {
        result(self?.currentConnectivityStatus ?? "wifi")
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    shareChannel = FlutterMethodChannel(name: "daily_planner/native_share", binaryMessenger: messenger)
    shareChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "shareText" {
        let args = call.arguments as? [String: Any]
        let text = args?["text"] as? String ?? ""
        let subject = args?["subject"] as? String

        if let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController {
            self?.shareText(text: text, subject: subject, controller: rootVC, result: result)
        } else {
            result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Could not find root view controller", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    healthChannel = FlutterMethodChannel(name: "daily_planner/native_health", binaryMessenger: messenger)
    healthChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleHealthCalls(call: call, result: result)
    }

    let googleAuthChannel = FlutterMethodChannel(name: "daily_planner/native_google_signin", binaryMessenger: messenger)
    googleAuthChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "signIn":
        result(FlutterError(
          code: "UNSUPPORTED_ON_IOS",
          message: "Native Google Sign-In channel is optimized for Android Google Identity. On iOS, authenticate via standard Firebase Auth or web credentials.",
          details: nil
        ))
      case "signOut", "disconnect":
        result(true)
      case "getCurrentUser":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Alarm & Notification Handler

  private func handleAlarmCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scheduleNativeAlarm", "scheduleAlarm":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a Map", details: nil))
        return
      }

      let rawId = (args["id"] as? NSNumber)?.intValue ?? 0
      let id = rawId != 0 ? abs(rawId) : Int(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100000)) + 1
      let title = args["title"] as? String ?? "Medday Flow"
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
      let title = args["title"] as? String ?? "Medday Flow"
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
        DispatchQueue.main.async { result(granted) }
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
        DispatchQueue.main.async { result(granted) }
      }

    case "requestCriticalAlertPermission":
      if #available(iOS 12.0, *) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { granted, error in
          DispatchQueue.main.async { result(granted) }
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

  // MARK: - Persistent Key-Value Preferences Handler

  private func handlePreferencesCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let defaults = UserDefaults.standard
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "getAll":
      var dict: [String: Any] = [:]
      let defaultsDict = defaults.dictionaryRepresentation()
      for (key, val) in defaultsDict {
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

  // MARK: - Biometric Authentication Handler

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

      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
        DispatchQueue.main.async {
          var code = "AUTH_UNAVAILABLE"
          var message = error?.localizedDescription ?? "Authentication is not available on this device."

          if let laError = error as? LAError {
            switch laError.code {
            case .passcodeNotSet:
              code = "PASSCODE_NOT_SET"
              message = "Please set a passcode in Settings to secure your device."
            case .biometryNotEnrolled:
              code = "BIOMETRY_NOT_ENROLLED"
              message = "No biometrics enrolled. Falling back to passcode."
            case .biometryNotAvailable:
              code = "BIOMETRY_NOT_AVAILABLE"
              message = "Biometrics are not available right now."
            default:
              break
            }
          }

          result(FlutterError(code: code, message: message, details: nil))
        }
        return
      }

      context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: reason
      ) { success, authError in
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            var code = "AUTH_FAILED"
            var message = authError?.localizedDescription ?? "Authentication failed."

            if let laError = authError as? LAError {
              switch laError.code {
              case .userCancel:
                code = "USER_CANCELLED"
                message = "Authentication was cancelled."
              case .userFallback:
                code = "USER_FALLBACK"
                message = "User chose to enter passcode."
              case .authenticationFailed:
                code = "AUTH_FAILED"
                message = "Could not verify your identity. Please try again."
              case .biometryLockout:
                code = "BIOMETRY_LOCKOUT"
                message = "Biometrics locked. Please enter your passcode."
              default:
                break
              }
            }

            result(FlutterError(code: code, message: message, details: nil))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Network Connectivity Monitoring

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

  // MARK: - Native Apple Health (HealthKit) Handler

  private func parseDate(from string: String?) -> Date? {
    guard let string = string, !string.isEmpty else { return nil }

    // 1. Try ISO8601 with fractional seconds (Dart toIso8601String() default)
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: string) {
      return date
    }

    // 2. Try standard ISO8601
    let standardFormatter = ISO8601DateFormatter()
    standardFormatter.formatOptions = [.withInternetDateTime]
    if let date = standardFormatter.date(from: string) {
      return date
    }

    return nil
  }

  private func handleHealthCalls(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkAvailability":
      DispatchQueue.main.async { [weak self] in
        var isAvail = false
        let ex = CatchObjCException {
          isAvail = HKHealthStore.isHealthDataAvailable()
        }
        if ex == nil && isAvail && self?.getHealthStore() != nil {
          result(true)
        } else {
          result(false)
        }
      }

    case "requestPermissions":
      DispatchQueue.main.async { [weak self] in
        guard let store = self?.getHealthStore(),
              let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
          result(false)
          return
        }

        let typesToShare: Set<HKSampleType> = [mindfulType]
        let typesToRead: Set<HKObjectType> = [mindfulType]

        let reqException = CatchObjCException {
          store.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            DispatchQueue.main.async {
              if let error = error {
                result(FlutterError(code: "HEALTH_AUTH_ERROR", message: error.localizedDescription, details: nil))
              } else {
                result(success)
              }
            }
          }
        }

        if let ex = reqException {
          print("⚠️ HealthKit requestAuthorization exception: \(ex.name.rawValue) - \(ex.reason ?? "")")
          result(FlutterError(code: "HEALTHKIT_NOT_CONFIGURED", message: ex.reason ?? "HealthKit authorization exception", details: nil))
        }
      }

    case "checkPermissions":
      DispatchQueue.main.async { [weak self] in
        guard let store = self?.getHealthStore(),
              let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
          result(false)
          return
        }

        var status: HKAuthorizationStatus = .notDetermined
        let checkException = CatchObjCException {
          status = store.authorizationStatus(for: mindfulType)
        }

        if let ex = checkException {
          print("⚠️ HealthKit checkPermissions exception: \(ex.name.rawValue) - \(ex.reason ?? "")")
          result(false)
          return
        }

        result(status == .sharingAuthorized)
      }

    case "saveMedicationRecord":
      guard let store = self.getHealthStore(),
            let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession),
            let args = call.arguments as? [String: Any] else {
        DispatchQueue.main.async {
          result(FlutterError(code: "HEALTHKIT_NOT_AVAILABLE", message: "HealthKit is not available or arguments are invalid", details: nil))
        }
        return
      }

      let now = Date()
      let scheduledStr = args["scheduledTime"] as? String
      let actualStr = args["actualTime"] as? String

      let parsedDate = parseDate(from: actualStr) ?? parseDate(from: scheduledStr) ?? now

      // CRITICAL HEALTHKIT REQUIREMENT:
      // HealthKit strictly forbids future dates for mindfulness sessions!
      // If end date or start date is in the future, HealthKit raises _HKObjectValidationFailureException.
      var endDate = parsedDate
      if endDate > now {
        endDate = now
      }
      var startDate = endDate.addingTimeInterval(-60) // 1-minute session ending at endDate
      if startDate >= endDate {
        startDate = endDate.addingTimeInterval(-1)
      }

      let recordId = args["recordId"] as? String ?? UUID().uuidString
      let safeSyncId = String(recordId.prefix(99))

      let metadata: [String: Any] = [
        "RecordId": recordId,
        "MedicationName": args["medicationName"] as? String ?? "Medication Intake",
        "Dosage": "\(args["dosage"] ?? "")",
        "DosageUnit": args["dosageUnit"] as? String ?? "",
        "Status": args["status"] as? String ?? "taken",
        "LogicalDate": args["logicalDate"] as? String ?? "",
        "Source": "MedDay Flow",
        HKMetadataKeySyncIdentifier: safeSyncId,
        HKMetadataKeySyncVersion: NSNumber(value: 1)
      ]

      var sample: HKCategorySample?
      let sampleException = CatchObjCException {
        sample = HKCategorySample(
          type: mindfulType,
          value: HKCategoryValue.notApplicable.rawValue,
          start: startDate,
          end: endDate,
          metadata: metadata
        )
      }

      if let ex = sampleException, sample == nil {
        print("⚠️ HealthKit HKCategorySample creation exception: \(ex.name.rawValue) - \(ex.reason ?? "")")
        DispatchQueue.main.async {
          result(FlutterError(code: "SAMPLE_CREATION_FAILED", message: ex.reason ?? "Failed to create HealthKit sample", details: nil))
        }
        return
      }

      guard let sampleToSave = sample else {
        DispatchQueue.main.async {
          result(FlutterError(code: "SAMPLE_NIL", message: "HealthKit sample is nil", details: nil))
        }
        return
      }

      let saveException = CatchObjCException {
        store.save(sampleToSave) { success, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "HEALTHKIT_SAVE_FAILED", message: error.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }
      }

      if let ex = saveException {
        print("⚠️ HealthKit save exception: \(ex.name.rawValue) - \(ex.reason ?? "")")
        DispatchQueue.main.async {
          result(FlutterError(code: "HEALTHKIT_EXCEPTION", message: ex.reason ?? "HealthKit save threw exception", details: nil))
        }
      }

    case "fetchMedicationRecords":
      guard let store = self.getHealthStore(),
            let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
        DispatchQueue.main.async { result([]) }
        return
      }

      let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
      let query = HKSampleQuery(sampleType: mindfulType, predicate: nil, limit: 100, sortDescriptors: [sortDescriptor]) { _, samples, error in
        DispatchQueue.main.async {
          if let error = error {
            print("HealthKit Fetch Error: \(error.localizedDescription)")
            result([])
            return
          }

          var records: [[String: Any]] = []
          let iso = ISO8601DateFormatter()
          for sample in (samples as? [HKCategorySample] ?? []) {
            let meta = sample.metadata ?? [:]
            let dict: [String: Any] = [
              "recordId": meta["RecordId"] as? String ?? (meta[HKMetadataKeySyncIdentifier] as? String) ?? sample.uuid.uuidString,
              "medicationName": meta["MedicationName"] as? String ?? "Medication Intake",
              "dosage": meta["Dosage"] as? String ?? "",
              "dosageUnit": meta["DosageUnit"] as? String ?? "",
              "status": meta["Status"] as? String ?? "taken",
              "logicalDate": meta["LogicalDate"] as? String ?? "",
              "syncedAt": iso.string(from: sample.startDate),
              "platform": "Apple Health"
            ]
            records.append(dict)
          }
          result(records)
        }
      }

      let queryException = CatchObjCException {
        store.execute(query)
      }

      if let ex = queryException {
        print("⚠️ HealthKit execute query exception: \(ex.name.rawValue) - \(ex.reason ?? "")")
        DispatchQueue.main.async { result([]) }
      }

    case "revokePermissions":
      DispatchQueue.main.async { result(true) }

    default:
      DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
    }
  }
}