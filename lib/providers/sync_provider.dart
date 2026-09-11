import 'dart:async';
import 'package:daily_planner/models/sync_config_model.dart';
import 'package:daily_planner/services/sync/google_calendar_sync_service.dart';
import 'package:daily_planner/services/sync/sync_manager.dart';
import 'package:daily_planner/services/native_connectivity_service.dart';
import 'package:daily_planner/services/native_google_sign_in.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SyncProvider extends ChangeNotifier {
  final SyncManager _syncManager;

  SyncConfig _config = const SyncConfig();
  List<SyncLogEntry> _logs = [];

  SyncStatus _calendarStatus = SyncStatus.idle;
  SyncStatus _tasksStatus = SyncStatus.idle;
  SyncStatus _healthStatus = SyncStatus.idle;
  bool _isSyncingAll = false;
  String? _googleAccessToken;

  // Connectivity re-sync
  StreamSubscription<CustomConnectivityResult>? _connectivitySubscription;
  bool _reconnectSyncPending = false;
  CustomConnectivityResult _lastConnectivity = CustomConnectivityResult.none;

  SyncProvider({SyncManager? syncManager})
      : _syncManager = syncManager ?? SyncManager() {
    _initialize();
  }

  // Getters
  SyncConfig get config => _config;
  List<SyncLogEntry> get logs => _logs;

  SyncStatus get calendarStatus => _calendarStatus;
  SyncStatus get tasksStatus => _tasksStatus;
  SyncStatus get healthStatus => _healthStatus;
  bool get isSyncingAll => _isSyncingAll;

  bool get isCalendarEnabled => _config.googleCalendarEnabled;
  bool get isTasksEnabled => _config.googleTasksEnabled;
  bool get isHealthEnabled => _config.healthSyncEnabled;

  String? get googleEmail => _config.googleAccountEmail;
  bool get isGoogleConnected => _config.googleAccountEmail != null && _config.googleAccountEmail!.isNotEmpty;
  bool get isHealthConnected => _config.healthPermissionGranted;

  DateTime? get lastCalendarSync => _config.lastCalendarSync;
  DateTime? get lastTasksSync => _config.lastTasksSync;
  DateTime? get lastHealthSync => _config.lastHealthSync;

  Future<void> _initialize() async {
    _config = await _syncManager.loadConfig();
    _logs = await _syncManager.loadLogs();

    // Auto-detect currently signed in Firebase / Google user email if not set
    if (_config.googleAccountEmail == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        _config = _config.copyWith(googleAccountEmail: user.email);
        await _syncManager.saveConfig(_config);
      }
    }

    // Check health permissions
    final hasHealth = await _syncManager.healthService.isHealthPermissionGranted();
    if (hasHealth != _config.healthPermissionGranted) {
      _config = _config.copyWith(healthPermissionGranted: hasHealth);
      await _syncManager.saveConfig(_config);
    }

    // Wire connectivity listener to auto-sync on reconnect
    _connectivitySubscription?.cancel();
    _connectivitySubscription = NativeConnectivityService.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    notifyListeners();
  }

  Future<void> reload() async {
    await _initialize();
  }

  // Configuration Toggles
  Future<void> toggleCalendarSync(bool value) async {
    _config = _config.copyWith(googleCalendarEnabled: value);
    await _syncManager.saveConfig(_config);
    notifyListeners();
  }

  Future<void> toggleTasksSync(bool value) async {
    _config = _config.copyWith(googleTasksEnabled: value);
    await _syncManager.saveConfig(_config);
    notifyListeners();
  }

  Future<void> toggleHealthSync(bool value) async {
    if (value && !_config.healthPermissionGranted) {
      final granted = await requestHealthPermissions();
      if (!granted) {
        return;
      }
    }
    _config = _config.copyWith(healthSyncEnabled: value);
    await _syncManager.saveConfig(_config);
    notifyListeners();
  }

  Future<void> setAutoSyncInterval(int minutes) async {
    _config = _config.copyWith(autoSyncIntervalMinutes: minutes);
    await _syncManager.saveConfig(_config);
    notifyListeners();
  }

  // Google Account Management
  Future<bool> connectGoogleAccount({String? email, String? token}) async {
    try {
      String? connectedEmail = email;
      String? accessToken = token;

      if (connectedEmail == null) {
        final account = await NativeGoogleSignIn.signIn();
        if (account != null) {
          connectedEmail = account.email;
          accessToken = account.idToken;
        }
      }

      if (connectedEmail != null) {
        _googleAccessToken = accessToken;
        _config = _config.copyWith(
          googleAccountEmail: connectedEmail,
          googleCalendarEnabled: true,
          googleTasksEnabled: true,
        );
        await _syncManager.saveConfig(_config);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error connecting Google account: $e');
      return false;
    }
  }

  Future<void> disconnectGoogleAccount() async {
    await NativeGoogleSignIn.disconnect();
    _googleAccessToken = null;
    _config = _config.copyWith(
      googleAccountEmail: null,
      googleCalendarEnabled: false,
      googleTasksEnabled: false,
    );
    await _syncManager.saveConfig(_config);
    _calendarStatus = SyncStatus.disconnected;
    _tasksStatus = SyncStatus.disconnected;
    notifyListeners();
  }

  // Health Permissions
  Future<bool> requestHealthPermissions() async {
    _healthStatus = SyncStatus.syncing;
    notifyListeners();

    final granted = await _syncManager.healthService.requestHealthPermissions();
    _config = _config.copyWith(
      healthPermissionGranted: granted,
      healthSyncEnabled: granted ? _config.healthSyncEnabled : false,
    );
    await _syncManager.saveConfig(_config);
    _healthStatus = granted ? SyncStatus.idle : SyncStatus.error;
    notifyListeners();
    return granted;
  }

  Future<void> revokeHealthPermissions() async {
    await _syncManager.healthService.revokeHealthPermissions();
    _config = _config.copyWith(
      healthPermissionGranted: false,
      healthSyncEnabled: false,
    );
    await _syncManager.saveConfig(_config);
    _healthStatus = SyncStatus.disconnected;
    notifyListeners();
  }

  // Synchronization Operations
  Future<SyncResult> syncCalendar(List<Task> tasks) async {
    _calendarStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      final result = await _syncManager.syncGoogleCalendar(
        tasks,
        accessToken: _googleAccessToken,
      );
      _calendarStatus = result.isSuccess ? SyncStatus.success : SyncStatus.error;
      _config = await _syncManager.loadConfig();
      _logs = await _syncManager.loadLogs();
      notifyListeners();
      return result;
    } catch (e) {
      _calendarStatus = SyncStatus.error;
      notifyListeners();
      return SyncResult.failure('Calendar sync failed: $e');
    }
  }

  Future<SyncResult> syncGoogleTasks(List<Task> tasks) async {
    _tasksStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      final result = await _syncManager.syncGoogleTasks(
        tasks,
        accessToken: _googleAccessToken,
      );
      _tasksStatus = result.isSuccess ? SyncStatus.success : SyncStatus.error;
      _config = await _syncManager.loadConfig();
      _logs = await _syncManager.loadLogs();
      notifyListeners();
      return result;
    } catch (e) {
      _tasksStatus = SyncStatus.error;
      notifyListeners();
      return SyncResult.failure('Google Tasks sync failed: $e');
    }
  }

  Future<SyncResult> syncHealth(List<MedicationIntake> intakes) async {
    _healthStatus = SyncStatus.syncing;
    notifyListeners();

    try {
      final result = await _syncManager.syncHealthPlatform(intakes);
      _healthStatus = result.isSuccess ? SyncStatus.success : SyncStatus.error;
      _config = await _syncManager.loadConfig();
      _logs = await _syncManager.loadLogs();
      notifyListeners();
      return result;
    } catch (e) {
      _healthStatus = SyncStatus.error;
      notifyListeners();
      return SyncResult.failure('Health sync failed: $e');
    }
  }

  Future<void> syncAll({
    required List<Task> tasks,
    required List<MedicationIntake> intakes,
  }) async {
    _isSyncingAll = true;
    _calendarStatus = _config.googleCalendarEnabled ? SyncStatus.syncing : _calendarStatus;
    _tasksStatus = _config.googleTasksEnabled ? SyncStatus.syncing : _tasksStatus;
    _healthStatus = _config.healthSyncEnabled ? SyncStatus.syncing : _healthStatus;
    notifyListeners();

    try {
      if (_config.googleCalendarEnabled) {
        await _syncManager.syncGoogleCalendar(tasks, accessToken: _googleAccessToken);
        _calendarStatus = SyncStatus.success;
      }
      if (_config.googleTasksEnabled) {
        await _syncManager.syncGoogleTasks(tasks, accessToken: _googleAccessToken);
        _tasksStatus = SyncStatus.success;
      }
      if (_config.healthSyncEnabled) {
        await _syncManager.syncHealthPlatform(intakes);
        _healthStatus = SyncStatus.success;
      }

      _config = await _syncManager.loadConfig();
      _logs = await _syncManager.loadLogs();
    } catch (e) {
      debugPrint('Error syncing all: $e');
    } finally {
      _isSyncingAll = false;
      notifyListeners();
    }
  }

  Future<void> clearLogs() async {
    _logs = [];
    await _syncManager.addLog(SyncLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceType: SyncServiceType.googleCalendar,
      timestamp: DateTime.now(),
      isSuccess: true,
      message: 'Sync logs reset',
    ));
    _logs = await _syncManager.loadLogs();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Connectivity-triggered re-sync
  // -------------------------------------------------------------------------

  void _onConnectivityChanged(CustomConnectivityResult result) {
    final wasOffline = _lastConnectivity == CustomConnectivityResult.none;
    final isNowOnline = result != CustomConnectivityResult.none;
    _lastConnectivity = result;

    if (wasOffline && isNowOnline && !_reconnectSyncPending) {
      _reconnectSyncPending = true;
      debugPrint('SyncProvider: device reconnected — triggering pending sync');
      // Small delay to let Firestore flush its write queue first
      Future.delayed(const Duration(seconds: 3), _triggerReconnectSync);
    }
  }

  Future<void> _triggerReconnectSync() async {
    _reconnectSyncPending = false;

    // Only run if any external sync service is enabled and Google is connected
    if (!isGoogleConnected &&
        !_config.googleCalendarEnabled &&
        !_config.googleTasksEnabled &&
        !_config.healthSyncEnabled) {
      return;
    }

    // We don't have tasks/intakes here — log a pending sync entry so the
    // user can see the reconnection was detected in the sync log.
    await _syncManager.addLog(SyncLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceType: SyncServiceType.googleCalendar,
      timestamp: DateTime.now(),
      isSuccess: true,
      message: '📡 Device reconnected — Firestore writes flushed. Open the app to complete external service sync.',
    ));

    _logs = await _syncManager.loadLogs();
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
