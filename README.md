# 🗓️ Daily Planner — Modern Flutter & Native Android Productivity App

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-%23039BE5.svg?style=for-the-badge&logo=firebase)](https://firebase.google.com/)
[![Kotlin](https://img.shields.io/badge/Kotlin-%237F52FF.svg?style=for-the-badge&logo=kotlin&logoColor=white)](https://kotlinlang.org/)
[![Android 14+ Ready](https://img.shields.io/badge/Android%2014%2B-Compatible-3DDC84.svg?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com/)

**Daily Planner** is a high-performance, offline-first personal productivity, medication scheduling, and habit-tracking application built with Flutter, Firebase, and custom Native Android Kotlin platform services. Engineered with a zero-bloat philosophy, it delivers enterprise-grade reliability, circadian-aware scheduling, bi-directional cloud sync, and custom canvas-rendered analytics.

---

## 🌟 Key Highlights & Architecture

- **⚡ Zero External Package Bloat:** Core capabilities like state management, alarm scheduling, biometrics, charts, connectivity, preferences, and sharing are implemented using pure Flutter and custom Native Kotlin platform channels rather than bulky third-party dependencies.
- **🌙 Circadian / Waking Day Engine:** Proprietary logical day algorithm with customizable cutoffs (e.g., 4:00 AM) that aligns medication and habit tracking with real human sleep cycles instead of strict midnight calendar flips.
- **⏰ Custom Native Android Alarm Engine:** 100% custom Kotlin implementation using `AlarmManager`, Foreground Services, WakeLocks, and Boot Receivers with OEM battery optimization bypasses (Xiaomi, Samsung, Oppo, Vivo, Infinix, Tecno).
- **🔄 Universal Sync Hub:** Bi-directional synchronization with Google Calendar, Google Tasks, and Apple Health / Health Connect with smart conflict resolution.
- **📊 Canvas-Rendered Analytics:** High-performance custom `CustomPainter` bar and pie charts rendered directly on the Flutter canvas with zero chart library overhead.
- **🛡️ Native Security & Biometrics:** Passkey, Fingerprint, and Face Unlock via Android Credential Manager & BiometricPrompt.

---

## ✨ Features Breakdown

### 1. 📋 Smart Task & Habit Management
- **Task Types:** One-time, Daily, Weekly, and Monthly recurring tasks with customizable recurrence rules.
- **Detailed Metadata:** Priorities (High, Medium, Low), custom tags/categories, subtask checklists, and rich notes.
- **Auto-Reset & Streak System:** Automatically resets recurring tasks at the waking-day boundary while capturing completion stamps and calculating unbroken streak statistics.
- **Instant Local Search & Filtering:** Fast in-memory querying and multi-attribute filtering (priority, status, category, date range) without querying the backend repeatedly.

### 2. 💊 Medication & Circadian Intake Tracker
- **Logical Waking Day Boundary (4:00 AM Cutoff):** Late-night doses taken after midnight (12:00 AM – 3:59 AM) are correctly attributed to the current waking cycle's bedtime schedule.
- **Flexible Dosage Schedules:** Daily, specific weekdays, interval days (e.g., every 3 days), PRN (as-needed), and tapering regimens.
- **Inventory & Refill Alerts:** Tracks current pill/unit inventory, logs consumption, and alerts when stock is running low.
- **Adherence Metrics:** Visual progress indicators calculating taken, missed, and skipped medication rates.

### 3. ⏰ Custom Native Alarm & Notification System
- **Exact Alarms:** Deep integration with Android 12+ / 13+ / 14+ `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` permissions.
- **Persistent Alarm Service:** Kotlin foreground service and WakeLock mechanism ensure alarms ring reliably even during deep Android Doze Mode.
- **Device Reboot Resilience:** `BootReceiver` automatically restores and reschedules all active alarms after system reboots.
- **OEM Battery Optimization Guides:** Built-in actionable guide helping users configure background auto-start and whitelist restrictions on aggressive OEM skins (MIUI, OneUI, ColorOS, XOS, HiOS).
- **Interactive Notification Actions:** Complete, Snooze, or Dismiss directly from notifications or full-screen alerts.
- **In-App Alarm Tester:** Integrated 10-second alarm harness for immediate hardware and sound testing.

### 4. 🔄 Universal Cloud Sync & Integrations
- **Google Calendar Sync:** Exports and syncs one-time and recurring tasks with standardized `RRULE` format and private metadata tags.
- **Google Tasks Sync:** Two-way task synchronization keeping web and mobile task lists in perfect parity.
- **Health Connect & Apple Health:** Synchronizes medication logs and wellness activities with platform health databases.
- **Sync Configuration Engine:** Configurable sync modes (Real-Time, Periodic, Manual), conflict resolution policies (*Server Wins*, *Client Wins*, *Latest Timestamp*), and persistent audit logs.

### 5. 📈 Visual Analytics & Performance Insights
- **Custom-Engineered Charts:** Lightweight, responsive Bar and Pie charts drawn directly with Flutter `CustomPainter`.
- **Comprehensive Metrics:** Overall completion percentages, longest streaks, category distribution, daily breakdown, and productivity heatmaps.
- **Historical Logs:** Interactive task history timeline with granular completion timestamps.

### 6. 🔐 Native Authentication & Security
- **Multi-Auth Options:** Firebase Email/Password, Native Google Sign-In with Credential Manager API, and Passkey/Biometric login.
- **Credential Storage:** Native SharedPreferences with OS-level secure storage integration.
- **Password Autofill:** Full integration with Google and Apple native password autofill systems.

### 7. ☁️ Offline-First Firebase Infrastructure
- **Cloud Firestore Persistence:** Infinite cache offline storage (`CACHE_SIZE_UNLIMITED`) queues modifications and synchronizes instantaneously when connection resumes.
- **Firebase Cloud Messaging (FCM):** Multi-device push notification delivery with background handlers (`@pragma('vm:entry-point')`) and automatic token refresh handling.
- **Firebase Cloud Functions:** Backend serverless triggers for automated reminders, data cleanups, and administrative tasks.

---

## 🛠️ Technology Stack

| Layer | Technologies & Implementations |
| :--- | :--- |
| **Framework** | [Flutter](https://flutter.dev) (Dart SDK `^3.7.2`) |
| **State Management** | **Custom Pure Flutter Provider Architecture** (`InheritedNotifier`, `MultiProvider`, `ChangeNotifierProvider`) |
| **Backend & Cloud** | Firebase Core, Cloud Firestore (Offline Persistence), Firebase Auth, Firebase Cloud Messaging (FCM), Cloud Functions |
| **Native Android** | Kotlin, Android `AlarmManager`, `ForegroundService`, `BroadcastReceiver`, `CredentialManager`, `BiometricPrompt` |
| **Platform Channels** | Custom `MethodChannel` & `EventChannel` bindings for Alarms, Biometrics, Permissions, Connectivity, Timezone & Sharing |
| **Visuals & UI** | Material Design 3, Dynamic Light/Dark Theme System, Custom Canvas Painters |

---

## 📦 Key Dependencies (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter
  intl: 0.20.2                    # Date & Time formatting and localization
  firebase_core: ^3.14.0          # Firebase initialization
  cloud_firestore: ^5.6.9         # Offline-first NoSQL cloud database
  firebase_auth: ^5.6.0           # Secure user authentication
  firebase_messaging: ^15.2.7     # Multi-device push notifications
  http: ^1.3.0                    # REST API communication for Cloud Sync APIs
  cupertino_icons: ^1.0.8         # iOS companion icons

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_launcher_icons: ^0.14.4 # Automated multi-platform app icon generation
  flutter_lints: ^6.0.0          # Recommended Flutter linting rules
```

---

## 🧱 Project Structure

```text
daily_planner/
├── android/
│   └── app/src/main/kotlin/com/example/daily_planner/
│       ├── AlarmForegroundService.kt     # Native foreground service for alarms
│       ├── AlarmReceiver.kt              # Alarm broadcast trigger & full-screen intent
│       ├── AlarmScheduler.kt             # Exact alarm scheduling via AlarmManager
│       ├── AlarmStorage.kt               # Persistent alarm metadata store
│       ├── BootReceiver.kt               # Device reboot reschedule handler
│       ├── MainActivity.kt               # Platform channel bridge (Alarms, Biometrics, etc.)
│       ├── NativeGoogleAuthHandler.kt    # Native Credential Manager Google Sign-In
│       └── NativePreferencesHandler.kt   # Native SharedPreferences channel
├── Functions/                            # Firebase Cloud Functions (Node.js)
├── lib/
│   ├── models/
│   │   └── sync_config_model.dart        # Sync integration configuration & logs model
│   ├── providers/
│   │   ├── auth_provider.dart            # Reactive auth state container
│   │   ├── medication_provider.dart      # Medication state & intake scheduler
│   │   ├── settings_provider.dart        # App preferences & language state
│   │   ├── sync_provider.dart            # Cloud sync manager state provider
│   │   ├── task_provider.dart            # Task CRUD, filters, and streak management
│   │   └── theme_provider.dart           # Light/Dark/System theme switcher
│   ├── screens/
│   │   ├── add_medication_page.dart      # Medication & schedule creation screen
│   │   ├── additemPage.dart              # Task creation screen
│   │   ├── home.dart                     # Main dashboard & task feed
│   │   ├── itemdetailedit.dart           # Task editing & configuration
│   │   ├── itemdetailpage.dart           # Task detail view with checklist
│   │   ├── login.dart / signup.dart      # Authentication screens
│   │   ├── medication_detail_page.dart   # Medication history & dosage details
│   │   ├── medication_list_page.dart     # Medication management hub
│   │   ├── performance.dart              # Overview performance dashboard
│   │   ├── settings.dart                 # App settings & passkey manager
│   │   ├── sync_integrations_page.dart   # Google Calendar/Tasks & Health sync hub
│   │   ├── taskInsights.dart             # Deep task analytics with custom charts
│   │   └── taskinsights/                 # Analytics helper widgets & logic
│   ├── services/
│   │   ├── custom_state_management.dart  # Pure Flutter InheritedNotifier Provider engine
│   │   ├── native_biometric_service.dart # Biometric & Passkey channel service
│   │   ├── native_connectivity_service.dart # Real-time network state listener
│   │   ├── native_google_sign_in.dart    # Native Google Auth channel
│   │   ├── native_preferences_service.dart # Fast native storage service
│   │   ├── native_share_service.dart     # System share intent channel
│   │   ├── native_timezone_service.dart  # Native timezone resolver
│   │   └── sync/
│   │       ├── google_calendar_sync_service.dart # Google Calendar API sync
│   │       ├── google_tasks_sync_service.dart    # Google Tasks API sync
│   │       ├── health_sync_service.dart          # Health Connect / Apple Health sync
│   │       └── sync_manager.dart                 # Master sync coordinator
│   ├── utils/
│   │   ├── Alarm_helper.dart             # Flutter-to-Native alarm service bridge
│   │   ├── app_theme.dart                # Material 3 Design System & Theme palettes
│   │   ├── catalog.dart / item.dart      # Core Task data models & catalogs
│   │   ├── drawer.dart                   # Custom animated navigation drawer
│   │   ├── native_permission_service.dart# Android 12-14 permission management
│   │   ├── passkey_auth_service.dart     # Passkey & biometric verification helper
│   │   ├── push_notifications.dart       # FCM configuration & foreground handler
│   │   ├── reset_task.dart               # Waking-day auto-reset logic
│   │   ├── Medicaltion Model/            # Circadian intake models & generator engine
│   │   └── performance_page/             # Analytics aggregators (Daily & Total tasks)
│   ├── widgets/
│   │   └── charts/                       # Canvas-rendered Custom Bar & Pie charts
│   ├── firebase_options.dart             # Firebase platform options
│   └── main.dart                         # Application entrypoint & initialization
└── test/
    ├── circadian_intake_engine_test.dart # Circadian 4:00 AM cutoff unit tests
    ├── medication_provider_test.dart     # Medication state unit tests
    └── sync_engine_test.dart             # Calendar & Tasks sync payload unit tests
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.7.2`)
- [Android Studio](https://developer.android.com/studio) / Xcode
- [Firebase CLI](https://firebase.google.com/docs/cli) installed & configured
- Physical Android Device (Recommended for testing exact alarms, OEM battery whitelist, and biometric sensors)

### Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/daily_planner.git
   cd daily_planner
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase:**
   - Place your `google-services.json` in `android/app/`
   - (Optional) Run `flutterfire configure` to refresh `firebase_options.dart`

4. **Run Unit & Engine Tests:**
   ```bash
   flutter test
   ```

5. **Build and Run on Android:**
   ```bash
   flutter run
   ```

---

## 🧪 Testing

The project includes an extensive suite of automated tests verifying core algorithmic integrity:

```bash
# Run all unit tests
flutter test

# Run Circadian Waking Day logic tests
flutter test test/circadian_intake_engine_test.dart

# Run Cloud Sync Engine payload tests
flutter test test/sync_engine_test.dart
```

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

