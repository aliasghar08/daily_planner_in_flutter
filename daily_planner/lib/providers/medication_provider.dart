import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:flutter/material.dart';

class MedicationProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Medication> _medications = [];
  List<MedicationSchedule> _schedules = [];
  List<MedicationIntake> _selectedDateIntakes = [];
  DateTime _selectedDate = MedicationIntake.getLogicalDate(DateTime.now());
  bool _isLoading = false;
  String? _errorMessage;
  String? _userId;

  StreamSubscription<QuerySnapshot>? _medicationsSubscription;
  StreamSubscription<QuerySnapshot>? _schedulesSubscription;
  final Map<String, StreamSubscription<QuerySnapshot>> _intakesSubscriptions = {};
  
  List<QueryDocumentSnapshot> _rawSchedulesDocs = [];
  final Map<String, MedicationIntake> _rawRecordedIntakes = {};

  // Getters
  List<Medication> get medications => List.unmodifiable(_medications);
  List<MedicationSchedule> get schedules => List.unmodifiable(_schedules);
  List<MedicationIntake> get selectedDateIntakes =>
      List.unmodifiable(_selectedDateIntakes);
  List<MedicationIntake> get todayIntakes => selectedDateIntakes;
  DateTime get selectedDate => _selectedDate;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Current circadian logical date (runs 4 AM to 3:59 AM next day)
  DateTime get currentLogicalDate => MedicationIntake.getLogicalDate(DateTime.now());

  /// Whether the currently viewed date is the active logical day
  bool get isSelectedDateToday {
    final sel = MedicationIntake.getLogicalDate(_selectedDate);
    final cur = currentLogicalDate;
    return sel.year == cur.year && sel.month == cur.month && sel.day == cur.day;
  }

  /// Whether current wall-clock time is in the bedtime/night cycle (9 PM - 4 AM)
  bool get isNightCycleActive {
    final h = DateTime.now().hour;
    return h >= 21 || h < 5;
  }

  /// Returns intakes that are actively "Due Now" or needing attention right now
  List<MedicationIntake> get dueNowIntakes {
    final now = DateTime.now();
    return _selectedDateIntakes.where((i) => i.isDueNow(now)).toList();
  }

  /// Returns the next upcoming intake scheduled in the future for today or tomorrow
  MedicationIntake? get nextUpcomingIntake {
    final now = DateTime.now();
    final upcoming = _selectedDateIntakes
        .where((i) => i.status == IntakeStatus.pending && i.scheduledTime.isAfter(now))
        .toList();
    if (upcoming.isNotEmpty) {
      upcoming.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      return upcoming.first;
    }
    return null;
  }

  // Adherence Stats for Selected Date
  int get totalIntakesCount => _selectedDateIntakes.length;
  int get takenIntakesCount =>
      _selectedDateIntakes.where((i) => i.status == IntakeStatus.taken).length;
  int get skippedIntakesCount =>
      _selectedDateIntakes.where((i) => i.status == IntakeStatus.skipped).length;
  int get pendingIntakesCount =>
      _selectedDateIntakes.where((i) => i.status == IntakeStatus.pending).length;
  int get missedIntakesCount =>
      _selectedDateIntakes.where((i) => i.status == IntakeStatus.missed).length;

  double get adherencePercentage {
    if (totalIntakesCount == 0) return 0.0;
    return takenIntakesCount / totalIntakesCount;
  }

  /// Apple Health style time-of-day groups: Morning, Afternoon, Evening, Night
  Map<String, List<MedicationIntake>> get intakesByTimeOfDay {
    final Map<String, List<MedicationIntake>> groups = {
      'Morning': [],
      'Afternoon': [],
      'Evening': [],
      'Night': [],
    };

    for (final intake in _selectedDateIntakes) {
      final hour = intake.scheduledTime.hour;
      if (hour >= 5 && hour < 12) {
        groups['Morning']!.add(intake);
      } else if (hour >= 12 && hour < 17) {
        groups['Afternoon']!.add(intake);
      } else if (hour >= 17 && hour < 21) {
        groups['Evening']!.add(intake);
      } else {
        // Night: 9 PM - 4:59 AM (Bedtime)
        groups['Night']!.add(intake);
      }
    }

    // Sort each group chronologically
    for (final key in groups.keys) {
      groups[key]!.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    }

    return groups;
  }

  /// Initialize and load all medication data for a user
  Future<void> loadMedications(String userId) async {
    _userId = userId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _medicationsSubscription?.cancel();
      _schedulesSubscription?.cancel();

      // 1. Fetch medications via stream
      _medicationsSubscription = _firestore
          .collection('users')
          .doc(userId)
          .collection('medications')
          .snapshots()
          .listen((snapshot) {
        _medications = snapshot.docs.map((doc) {
          return Medication.fromMap(doc.data(), doc.id);
        }).toList();
        _rebuildSchedulesAndIntakes();
      });

      // 2. Fetch schedules via stream
      _schedulesSubscription = _firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .snapshots()
          .listen((snapshot) {
        _rawSchedulesDocs = snapshot.docs;
        _rebuildSchedulesAndIntakes();
      });

    } catch (e) {
      debugPrint('❌ Error loading medications: $e');
      _errorMessage = 'Failed to load medications: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _rebuildSchedulesAndIntakes() {
    _schedules = _rawSchedulesDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final medId = data['medicationId'];
      Medication? matchedMed;
      try {
        matchedMed = _medications.firstWhere((m) => m.medicationId == medId);
      } catch (_) {
        matchedMed = null;
      }
      return MedicationSchedule.fromMap(data, doc.id, matchedMed);
    }).toList();

    _setupIntakeListeners(_selectedDate);
    _scheduleMedicationNotifications();
  }

  /// Change selected date (Apple Health calendar strip)
  Future<void> selectDate(DateTime date) async {
    _selectedDate = MedicationIntake.getLogicalDate(date);
    _setupIntakeListeners(_selectedDate);
  }

  /// Setup listeners for candidate intakes for logical date
  void _setupIntakeListeners(DateTime date) {
    if (_userId == null) return;

    final logicalDate = MedicationIntake.getLogicalDate(date);
    final startOfLogicalWindow = DateTime(logicalDate.year, logicalDate.month, logicalDate.day, 0, 0);
    final endOfLogicalWindow = DateTime(logicalDate.year, logicalDate.month, logicalDate.day + 1, 5, 0);

    for (var sub in _intakesSubscriptions.values) {
      sub.cancel();
    }
    _intakesSubscriptions.clear();
    _rawRecordedIntakes.clear();

    for (final medication in _medications) {
      _intakesSubscriptions[medication.medicationId] = _firestore
          .collection('users')
          .doc(_userId)
          .collection('medications')
          .doc(medication.medicationId)
          .collection('intakes')
          .where('scheduledTime',
              isGreaterThanOrEqualTo: startOfLogicalWindow.millisecondsSinceEpoch)
          .where('scheduledTime', isLessThanOrEqualTo: endOfLogicalWindow.millisecondsSinceEpoch)
          .snapshots()
          .listen((snapshot) {
        for (var change in snapshot.docChanges) {
          final doc = change.doc;
          if (change.type == DocumentChangeType.removed) {
            _rawRecordedIntakes.remove(doc.id);
          } else {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final scheduleId = data['scheduleId'];
              MedicationSchedule? sched;
              try {
                sched = _schedules.firstWhere((s) => s.scheduleId == scheduleId);
              } catch (_) {
                sched = null;
              }
              final intake = MedicationIntake.fromMap(data, doc.id, sched);
              _rawRecordedIntakes[intake.intakeId] = intake;
            } catch (e) {
              debugPrint('Error parsing recorded intake ${doc.id}: $e');
            }
          }
        }
        _computeFinalIntakes(logicalDate);
      });
    }

    _computeFinalIntakes(logicalDate);
  }

  void _computeFinalIntakes(DateTime logicalDate) {
    // 1. Generate scheduled intakes for this logical date
    final List<MedicationIntake> generatedIntakes = [];
    for (final schedule in _schedules) {
      generatedIntakes.addAll(schedule.generateIntakesForDate(logicalDate));
    }

    // 2. Merge: If a recorded intake exists in Firestore, use its status & actual time
    final List<MedicationIntake> resolvedIntakes = [];
    final now = DateTime.now();

    for (final candidate in generatedIntakes) {
      if (_rawRecordedIntakes.containsKey(candidate.intakeId)) {
        resolvedIntakes.add(_rawRecordedIntakes[candidate.intakeId]!);
      } else {
        // If not recorded yet and grace period has ended in the past, mark missed
        if (candidate.isOverdue(now) && logicalDate.isBefore(currentLogicalDate)) {
          resolvedIntakes.add(candidate.copyWith(status: IntakeStatus.missed));
        } else {
          resolvedIntakes.add(candidate);
        }
      }
    }

    // Also include any extra as-needed or ad-hoc recorded intakes for this logical date
    for (final recorded in _rawRecordedIntakes.values) {
      if (recorded.isForLogicalDate(logicalDate) &&
          !resolvedIntakes.any((i) => i.intakeId == recorded.intakeId)) {
        resolvedIntakes.add(recorded);
      }
    }

    resolvedIntakes.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    _selectedDateIntakes = resolvedIntakes;
    notifyListeners();
  }

  /// Mark an intake (taken, skipped, pending, etc.) and persist to Firestore
  Future<void> markIntake({
    required MedicationIntake intake,
    required IntakeStatus status,
    DateTime? actualTime,
    String? notes,
  }) async {
    if (_userId == null) return;

    MedicationIntake updated;
    if (status == IntakeStatus.taken) {
      updated = intake.markTaken(
        actualTime: actualTime ?? DateTime.now(),
        notes: notes,
      );
    } else if (status == IntakeStatus.skipped) {
      updated = intake.markSkipped(notes: notes);
    } else if (status == IntakeStatus.missed) {
      updated = intake.markMissed(notes: notes);
    } else {
      updated = intake.copyWith(
        status: IntakeStatus.pending,
        actualTime: null,
        notes: notes,
      );
    }

    // Update local state immediately for instant responsive UI
    final index = _selectedDateIntakes.indexWhere((i) => i.intakeId == intake.intakeId);
    if (index >= 0) {
      _selectedDateIntakes[index] = updated;
    } else {
      _selectedDateIntakes.add(updated);
    }
    notifyListeners();

    // Persist to Firestore: users/{userId}/medications/{medId}/intakes/{intakeId}
    try {
      final docRef = _firestore
          .collection('users')
          .doc(_userId)
          .collection('medications')
          .doc(intake.schedule.medication.medicationId)
          .collection('intakes')
          .doc(intake.intakeId);

      await docRef.set(updated.toMap(), SetOptions(merge: true));

      // If taken or skipped, cancel pending alarm for this intake
      if (status == IntakeStatus.taken || status == IntakeStatus.skipped) {
        final alarmId = _getNotificationId(intake.intakeId);
        await NativeAlarmHelper.cancelHybridAlarm(alarmId);
      }
    } catch (e) {
      debugPrint('❌ Error persisting intake: $e');
    }
  }

  /// Add or update a medication and its schedule
  Future<void> saveMedication({
    required Medication medication,
    required MedicationSchedule schedule,
  }) async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final userDoc = _firestore.collection('users').doc(_userId);

      // 1. Save medication document
      final medRef = userDoc.collection('medications').doc(medication.medicationId);
      await medRef.set(medication.toMap(), SetOptions(merge: true));

      // 2. Save schedule document
      final schedRef = userDoc.collection('schedules').doc(schedule.scheduleId);
      await schedRef.set(schedule.toMap(), SetOptions(merge: true));

      // 3. Update local collections
      final medIdx = _medications.indexWhere((m) => m.medicationId == medication.medicationId);
      if (medIdx >= 0) {
        _medications[medIdx] = medication;
      } else {
        _medications.insert(0, medication);
      }

      final schedIdx = _schedules.indexWhere((s) => s.scheduleId == schedule.scheduleId);
      if (schedIdx >= 0) {
        _schedules[schedIdx] = schedule;
      } else {
        _schedules.insert(0, schedule);
      }

      // 4. Refresh intakes for selected date via stream listener
      _setupIntakeListeners(_selectedDate);

      // 5. Schedule notification alarms
      _scheduleMedicationNotifications();
    } catch (e) {
      debugPrint('❌ Error saving medication: $e');
      _errorMessage = 'Failed to save medication: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a medication, its schedules, intakes, and scheduled alarms
  Future<void> deleteMedication(String medicationId) async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final userDoc = _firestore.collection('users').doc(_userId);

      // 1. Cancel alarms for all intakes belonging to this medication
      final schedulesToDelete =
          _schedules.where((s) => s.medication.medicationId == medicationId).toList();
      for (final s in schedulesToDelete) {
        for (final time in s.timesPerDay) {
          final dummyId = 'intake_${s.scheduleId}_${time.hour}_${time.minute}';
          final alarmId = _getNotificationId(dummyId);
          await NativeAlarmHelper.cancelHybridAlarm(alarmId);
        }
      }

      // 2. Delete medication intakes subcollection
      final intakesSnapshot = await userDoc
          .collection('medications')
          .doc(medicationId)
          .collection('intakes')
          .get();

      for (final doc in intakesSnapshot.docs) {
        await doc.reference.delete();
      }

      // 3. Delete medication doc
      await userDoc.collection('medications').doc(medicationId).delete();

      // 4. Delete associated schedules from Firestore
      for (final s in schedulesToDelete) {
        await userDoc.collection('schedules').doc(s.scheduleId).delete();
      }

      // 5. Update local state
      _medications.removeWhere((m) => m.medicationId == medicationId);
      _schedules.removeWhere((s) => s.medication.medicationId == medicationId);
      _selectedDateIntakes.removeWhere(
        (i) => i.schedule.medication.medicationId == medicationId,
      );
    } catch (e) {
      debugPrint('❌ Error deleting medication: $e');
      _errorMessage = 'Failed to delete medication: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Schedule notifications for all upcoming pending intakes today & tomorrow
  void _scheduleMedicationNotifications() {
    final now = DateTime.now();
    final logicalToday = MedicationIntake.getLogicalDate(now);
    final logicalTomorrow = logicalToday.add(const Duration(days: 1));

    for (final schedule in _schedules) {
      final med = schedule.medication;
      if (!med.isActive) continue;

      final todayIntakes = schedule.generateIntakesForDate(logicalToday);
      final tomorrowIntakes = schedule.generateIntakesForDate(logicalTomorrow);

      final allUpcoming = [...todayIntakes, ...tomorrowIntakes];

      for (final intake in allUpcoming) {
        // Calculate reminder time (apply reminderMinutesBefore if configured)
        final reminderTime = intake.scheduledTime.subtract(
          Duration(minutes: schedule.reminderMinutesBefore),
        );

        if (reminderTime.isAfter(now)) {
          final alarmId = _getNotificationId(intake.intakeId);
          final title = '💊 Time for ${med.name}';
          final body =
              'Take ${med.dosage} ${med.unit.name}${schedule.instructions != null && schedule.instructions!.isNotEmpty ? ' (${schedule.instructions})' : ''}';

          NativeAlarmHelper.scheduleHybridAlarm(
            id: alarmId,
            title: title,
            body: body,
            dateTime: reminderTime,
            payload: {
              'type': 'medication',
              'intakeId': intake.intakeId,
              'medicationId': med.medicationId,
            },
          ).catchError((e) {
            debugPrint('Error scheduling alarm for intake: $e');
          });
        }
      }
    }
  }

  /// Deterministic integer ID for notifications
  int _getNotificationId(String key) {
    return (key.hashCode.abs() % 100000000);
  }

  @override
  void dispose() {
    _medicationsSubscription?.cancel();
    _schedulesSubscription?.cancel();
    for (var sub in _intakesSubscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
