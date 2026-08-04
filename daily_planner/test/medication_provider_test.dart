import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Medication & Intake Models', () {
    test('Medication serialization and deserialization', () {
      final med = Medication(
        medicationId: 'med_123',
        name: 'Aspirin',
        dosage: 100.0,
        unit: DosageUnit.mg,
        color: '#e74c3c',
        icon: '💊',
        description: 'Take after meal',
        createdAt: DateTime(2026, 1, 1),
      );

      final map = med.toMap();
      expect(map['name'], 'Aspirin');
      expect(map['dosage'], 100.0);
      expect(map['unit'], 'mg');

      final fromMap = Medication.fromMap(map, 'med_123');
      expect(fromMap.medicationId, 'med_123');
      expect(fromMap.name, 'Aspirin');
      expect(fromMap.dosage, 100.0);
      expect(fromMap.unit, DosageUnit.mg);
    });

    test('MedicationSchedule serialization and parsing', () {
      final med = Medication(
        medicationId: 'med_123',
        name: 'Aspirin',
        dosage: 100.0,
        unit: DosageUnit.mg,
        color: '#e74c3c',
        icon: '💊',
        createdAt: DateTime(2026, 1, 1),
      );

      final schedule = MedicationSchedule(
        scheduleId: 'sched_123',
        medication: med,
        startDate: DateTime(2026, 1, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 21, minute: 0)],
        reminderMinutesBefore: 15,
        createdAt: DateTime(2026, 1, 1),
      );

      final map = schedule.toMap();
      expect(map['frequency'], 'daily');
      expect(map['timesPerDay'], [
        {'hour': 9, 'minute': 0},
        {'hour': 21, 'minute': 0},
      ]);

      final parsed = MedicationSchedule.fromMap(map, 'sched_123', med);
      expect(parsed.scheduleId, 'sched_123');
      expect(parsed.timesPerDay.length, 2);
      expect(parsed.timesPerDay.first.hour, 9);
      expect(parsed.timesPerDay.last.hour, 21);
    });

    test('MedicationIntake ID generation and status updates', () {
      final med = Medication(
        medicationId: 'med_123',
        name: 'Aspirin',
        dosage: 100.0,
        unit: DosageUnit.mg,
        color: '#e74c3c',
        icon: '💊',
        createdAt: DateTime(2026, 1, 1),
      );

      final schedule = MedicationSchedule(
        scheduleId: 'sched_123',
        medication: med,
        startDate: DateTime(2026, 1, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 8, minute: 30)],
        reminderMinutesBefore: 15,
        createdAt: DateTime(2026, 1, 1),
      );

      final scheduledTime = DateTime(2026, 8, 4, 8, 30);
      final intakeId = MedicationIntake.generateIntakeId('sched_123', scheduledTime);
      expect(intakeId, 'sched_123_2026-08-04_0830');

      final intake = MedicationIntake(
        intakeId: intakeId,
        schedule: schedule,
        scheduledTime: scheduledTime,
      );

      expect(intake.status, IntakeStatus.pending);

      final takenIntake = intake.copyWith(
        status: IntakeStatus.taken,
        actualTime: DateTime(2026, 8, 4, 8, 35),
      );

      expect(takenIntake.status, IntakeStatus.taken);
      expect(takenIntake.actualTime, isNotNull);
    });
  });
}
