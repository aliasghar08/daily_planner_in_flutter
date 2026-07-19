// lib/services/medication_manager.dart
// import 'package:daily_planner/models/medication_enums.dart';
// import 'package:daily_planner/models/medication_intake.dart';
// import 'package:daily_planner/models/medication_model.dart';
// import 'package:daily_planner/models/medication_schedule_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';

class MedicationManager {
  final Map<String, Medication> _medications = {};
  final Map<String, MedicationSchedule> _schedules = {};
  final Map<String, MedicationIntake> _intakes = {};

  String addMedication(Medication medication) {
    _medications[medication.medicationId] = medication;
    return medication.medicationId;
  }

  String createSchedule(MedicationSchedule schedule) {
    _schedules[schedule.scheduleId] = schedule;
    _generateUpcomingIntakes(schedule);
    return schedule.scheduleId;
  }

  void _generateUpcomingIntakes(
    MedicationSchedule schedule, {
    int daysAhead = 30,
  }) {
    final now = DateTime.now();
    final startDate = _isTodayOrAfter(schedule.startDate)
        ? schedule.startDate
        : DateTime.now();
    final endDate = schedule.endDate ?? now.add(Duration(days: daysAhead));

    // Generate intakes for date range
    final newIntakes = schedule.generateIntakesForDateRange(startDate, endDate);
    
    for (final intake in newIntakes) {
      // Only add if it doesn't already exist
      if (!_intakes.containsKey(intake.intakeId) &&
          intake.scheduledTime.isAfter(now.subtract(const Duration(minutes: 30)))) {
        _intakes[intake.intakeId] = intake;
      }
    }
  }

  // ADDED: Regenerate intakes for all schedules
  void regenerateIntakes({int daysAhead = 30}) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    
    // Remove old pending intakes that are in the future (they'll be regenerated)
    _intakes.removeWhere((key, intake) => 
        intake.status == IntakeStatus.pending && 
        intake.scheduledTime.isAfter(now));
    
    // Regenerate intakes for all schedules
    for (final schedule in _schedules.values) {
      final endDate = schedule.endDate ?? now.add(Duration(days: daysAhead));
      final newIntakes = schedule.generateIntakesForDateRange(tomorrow, endDate);
      
      for (final intake in newIntakes) {
        if (!_intakes.containsKey(intake.intakeId)) {
          _intakes[intake.intakeId] = intake;
        }
      }
    }
  }

  // ADDED: Check and mark missed intakes
  void checkAndMarkMissedIntakes() {
    final now = DateTime.now();
    final thirtyMinutesAgo = now.subtract(const Duration(minutes: 30));
    
    for (final intake in _intakes.values) {
      if (intake.status == IntakeStatus.pending &&
          intake.scheduledTime.isBefore(thirtyMinutesAgo)) {
        final missedIntake = intake.markMissed();
        _intakes[intake.intakeId] = missedIntake;
      }
    }
  }

  // ADDED: Ensure today's intakes exist
  void ensureTodaysIntakes() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    for (final schedule in _schedules.values) {
      final todayIntakes = schedule.generateIntakesForDate(today);
      
      for (final intake in todayIntakes) {
        if (!_intakes.containsKey(intake.intakeId)) {
          _intakes[intake.intakeId] = intake;
        }
      }
    }
    
    checkAndMarkMissedIntakes();
  }

  bool _shouldTakeMedication(MedicationSchedule schedule, DateTime checkDate) {
    if (checkDate.isBefore(schedule.startDate)) return false;
    if (schedule.endDate != null && checkDate.isAfter(schedule.endDate!))
      return false;

    switch (schedule.frequency) {
      case MedicationFrequency.daily:
        return true;
      case MedicationFrequency.weekly:
        return schedule.daysOfWeek.contains(
          checkDate.weekday - 1,
        ); // Convert to 0-6 (Mon-Sun)
      case MedicationFrequency.custom:
        return schedule.specificDates.any(
          (date) =>
              date.year == checkDate.year &&
              date.month == checkDate.month &&
              date.day == checkDate.day,
        );
      case MedicationFrequency.monthly:
        return checkDate.day == schedule.startDate.day;
      case MedicationFrequency.asNeeded:
        return false;
    }
  }

  bool _isTodayOrAfter(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day ||
        date.isAfter(now);
  }

  List<MedicationIntake> getTodaysIntakes() {
    ensureTodaysIntakes(); // ← CHANGED: Ensure today's intakes exist
    
    final today = DateTime.now();
    final todaysIntakes = <MedicationIntake>[];

    for (final intake in _intakes.values) {
      if (intake.scheduledTime.year == today.year &&
          intake.scheduledTime.month == today.month &&
          intake.scheduledTime.day == today.day) {
        todaysIntakes.add(intake);
      }
    }

    todaysIntakes.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return todaysIntakes;
  }

  List<MedicationIntake> getUpcomingIntakes({int hoursAhead = 24}) {
    final now = DateTime.now();
    final endTime = now.add(Duration(hours: hoursAhead));

    final upcoming = <MedicationIntake>[];
    for (final intake in _intakes.values) {
      if (intake.scheduledTime.isAfter(now) &&
          intake.scheduledTime.isBefore(endTime) &&
          intake.status == IntakeStatus.pending) {
        upcoming.add(intake);
      }
    }

    upcoming.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return upcoming;
  }

  void updateIntake(MedicationIntake updatedIntake) {
    _intakes[updatedIntake.intakeId] = updatedIntake;
  }

  // Getters for accessing data
  List<Medication> get medications => _medications.values.toList();
  List<MedicationSchedule> get schedules => _schedules.values.toList();
  List<MedicationIntake> get allIntakes => _intakes.values.toList();

  // Get medications for a specific date
  List<MedicationIntake> getIntakesForDate(DateTime date) {
    ensureTodaysIntakes(); // ← CHANGED: Ensure intakes exist
    
    return _intakes.values.where((intake) {
      return intake.scheduledTime.year == date.year &&
          intake.scheduledTime.month == date.month &&
          intake.scheduledTime.day == date.day;
    }).toList();
  }

  void deleteMedication(String medicationId) {
    _medications.remove(medicationId);

    final schedulesToRemove =
        _schedules.values
            .where(
              (schedule) => schedule.medication.medicationId == medicationId,
            )
            .map((schedule) => schedule.scheduleId)
            .toList();

    for (final scheduleId in schedulesToRemove) {
      if (scheduleId != null) {
        _schedules.remove(scheduleId);
      }
    }

    final intakesToRemove =
        _intakes.values
            .where(
              (intake) =>
                  intake.schedule.medication.medicationId == medicationId,
            )
            .map((intake) => intake.intakeId)
            .toList();

    for (final intakeId in intakesToRemove) {
      _intakes.remove(intakeId);
    }
  }

  void deleteSchedule(String scheduleId) {
    _schedules.remove(scheduleId);

    final intakesToRemove =
        _intakes.values
            .where((intake) => intake.schedule.scheduleId == scheduleId)
            .map((intake) => intake.intakeId)
            .toList();

    for (final intakeId in intakesToRemove) {
      _intakes.remove(intakeId);
    }
  }

  void clearSchedules() {
    _schedules.clear();
    _intakes.clear();
  }

  void clearIntakes() {
    _intakes.clear();
  }

  void addIntake(MedicationIntake intake) {
    _intakes.putIfAbsent(intake.intakeId, () => intake);
  }

  // ADDED: Get upcoming days count
  int getDaysUntilNextIntake() {
    final upcoming = getUpcomingIntakes(hoursAhead: 168); // 7 days
    if (upcoming.isEmpty) return -1;
    
    final nextIntake = upcoming.first;
    final now = DateTime.now();
    return nextIntake.scheduledTime.difference(now).inDays;
  }

  // ADDED: Get statistics
  Map<String, int> getIntakeStatistics() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    
    final todaysIntakes = getIntakesForDate(today);
    final takenToday = todaysIntakes.where((i) => i.status == IntakeStatus.taken).length;
    final missedToday = todaysIntakes.where((i) => i.status == IntakeStatus.missed).length;
    final pendingToday = todaysIntakes.where((i) => i.status == IntakeStatus.pending).length;
    
    final tomorrowsIntakes = getIntakesForDate(tomorrow);
    
    return {
      'total': _intakes.length,
      'takenToday': takenToday,
      'missedToday': missedToday,
      'pendingToday': pendingToday,
      'upcomingTomorrow': tomorrowsIntakes.length,
    };
  }
}