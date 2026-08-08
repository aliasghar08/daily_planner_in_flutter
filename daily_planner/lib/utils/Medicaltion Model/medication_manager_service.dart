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

  String addSchedule(MedicationSchedule schedule) => createSchedule(schedule);

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
    final logicalDate = (date.hour == 0 && date.minute == 0 && date.second == 0)
        ? DateTime(date.year, date.month, date.day)
        : MedicationIntake.getLogicalDate(date);
    ensureIntakesForDate(logicalDate);
    return _intakes.values.where((intake) {
      return intake.isForLogicalDate(logicalDate);
    }).toList();
  }

  void ensureTodaysIntakes() {
    ensureIntakesForDate(MedicationIntake.getLogicalDate(DateTime.now()));
  }

  void ensureIntakesForDate(DateTime date) {
    final logicalDate = (date.hour == 0 && date.minute == 0 && date.second == 0)
        ? DateTime(date.year, date.month, date.day)
        : MedicationIntake.getLogicalDate(date);
    for (final schedule in _schedules.values) {
      final generated = schedule.generateIntakesForDate(logicalDate);
      for (final intake in generated) {
        if (!_intakes.containsKey(intake.intakeId)) {
          _intakes[intake.intakeId] = intake;
        }
      }
    }
  }

  void regenerateIntakes() {
    final now = DateTime.now();
    final logicalToday = MedicationIntake.getLogicalDate(now);
    final logicalTomorrow = logicalToday.add(const Duration(days: 1));
    ensureIntakesForDate(logicalToday);
    ensureIntakesForDate(logicalTomorrow);
  }

  void checkAndMarkMissedIntakes() {
    final now = DateTime.now();
    for (final key in _intakes.keys.toList()) {
      final intake = _intakes[key]!;
      if (intake.status == IntakeStatus.pending && intake.isOverdue(now)) {
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