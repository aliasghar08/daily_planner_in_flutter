// lib/services/medication_manager.dart

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
    final startDate =
        _isTodayOrAfter(schedule.startDate)
            ? schedule.startDate
            : DateTime.now();
    final endDate =
        schedule.endDate ?? DateTime.now().add(Duration(days: daysAhead));

    DateTime currentDate = startDate;
    while (currentDate.isBefore(endDate) ||
        currentDate.isAtSameMomentAs(endDate)) {
      if (_shouldTakeMedication(schedule, currentDate)) {
        for (final intakeTime in schedule.timesPerDay) {
          final scheduledDateTime = DateTime(
            currentDate.year,
            currentDate.month,
            currentDate.day,
            intakeTime.hour,
            intakeTime.minute,
          );

          // Only create if not already exists and is in the future
          if (scheduledDateTime.isAfter(
            DateTime.now().subtract(Duration(minutes: 30)),
          )) {
            final intake = MedicationIntake(
              schedule: schedule,
              scheduledTime: scheduledDateTime,
            );
            _intakes[intake.intakeId] = intake;
          }
        }
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }
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
      case MedicationFrequency.asNeeded:
        return false; // Implement based on your needs
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
    return _intakes.values.where((intake) {
      return intake.scheduledTime.year == date.year &&
          intake.scheduledTime.month == date.month &&
          intake.scheduledTime.day == date.day;
    }).toList();
  }

  // Add these methods to your MedicationManager class

  void deleteMedication(String medicationId) {
    // Remove medication
    _medications.remove(medicationId);

    // Remove associated schedules
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

    // Remove associated intakes
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
    // Remove schedule
    _schedules.remove(scheduleId);

    // Remove associated intakes
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
}
