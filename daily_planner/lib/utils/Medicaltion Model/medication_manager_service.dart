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
    return schedule.scheduleId;
  }

  void addIntake(MedicationIntake intake) {
    _intakes[intake.intakeId] = intake;
  }

  void updateIntake(MedicationIntake updatedIntake) {
    _intakes[updatedIntake.intakeId] = updatedIntake;
  }

  List<Medication> get medications => _medications.values.toList();
  List<MedicationSchedule> get schedules => _schedules.values.toList();
  List<MedicationIntake> get allIntakes => _intakes.values.toList();

  List<MedicationIntake> getIntakesForDate(DateTime date) {
    ensureIntakesForDate(date);
    return _intakes.values.where((intake) {
      return intake.scheduledTime.year == date.year &&
          intake.scheduledTime.month == date.month &&
          intake.scheduledTime.day == date.day;
    }).toList();
  }

  void ensureTodaysIntakes() {
    ensureIntakesForDate(DateTime.now());
  }

  void ensureIntakesForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);

    for (final schedule in _schedules.values) {
      final schedStart = DateTime(
        schedule.startDate.year,
        schedule.startDate.month,
        schedule.startDate.day,
      );

      if (startOfDay.isBefore(schedStart)) continue;
      if (schedule.endDate != null) {
        final schedEnd = DateTime(
          schedule.endDate!.year,
          schedule.endDate!.month,
          schedule.endDate!.day,
          23,
          59,
          59,
        );
        if (startOfDay.isAfter(schedEnd)) continue;
      }

      bool applies = false;
      switch (schedule.frequency) {
        case MedicationFrequency.daily:
          applies = true;
          break;
        case MedicationFrequency.weekly:
          final dayIdx = (date.weekday - 1) % 7; // 0=Mon, 6=Sun
          applies = schedule.daysOfWeek.contains(dayIdx);
          break;
        case MedicationFrequency.monthly:
          applies = (date.day == schedule.startDate.day);
          break;
        case MedicationFrequency.custom:
          applies = schedule.specificDates.any(
            (d) => d.year == date.year && d.month == date.month && d.day == date.day,
          );
          break;
        case MedicationFrequency.asNeeded:
          applies = false;
          break;
      }

      if (!applies) continue;

      for (final time in schedule.timesPerDay) {
        final scheduledTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );

        final intakeId = MedicationIntake.generateIntakeId(
          schedule.scheduleId,
          scheduledTime,
        );

        if (!_intakes.containsKey(intakeId)) {
          _intakes[intakeId] = MedicationIntake(
            intakeId: intakeId,
            schedule: schedule,
            scheduledTime: scheduledTime,
          );
        }
      }
    }
  }

  void regenerateIntakes() {
    final now = DateTime.now();
    ensureIntakesForDate(now);
    ensureIntakesForDate(now.add(const Duration(days: 1)));
  }

  void checkAndMarkMissedIntakes() {
    final now = DateTime.now();
    for (final key in _intakes.keys.toList()) {
      final intake = _intakes[key]!;
      if (intake.status == IntakeStatus.pending &&
          intake.scheduledTime.add(const Duration(hours: 2)).isBefore(now)) {
        _intakes[key] = intake.markMissed();
      }
    }
  }

  void clear() {
    _medications.clear();
    _schedules.clear();
    _intakes.clear();
  }

  void deleteMedication(String medicationId) {
    _medications.remove(medicationId);
    _schedules.removeWhere(
      (key, schedule) => schedule.medication.medicationId == medicationId,
    );
    _intakes.removeWhere(
      (key, intake) => intake.schedule.medication.medicationId == medicationId,
    );
  }
}