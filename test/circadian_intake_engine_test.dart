import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Circadian-Aware Logical Date (4:00 AM Cutoff)', () {
    test('Correctly maps timestamps before and after 4:00 AM to logical health days', () {
      // 11:59 PM on Aug 7 -> Logical day Aug 7
      final t1 = DateTime(2026, 8, 7, 23, 59);
      expect(MedicationIntake.getLogicalDate(t1), DateTime(2026, 8, 7));

      // 12:00 AM Midnight on Aug 8 -> Still logical day Aug 7 (Bedtime cycle)
      final t2 = DateTime(2026, 8, 8, 0, 0);
      expect(MedicationIntake.getLogicalDate(t2), DateTime(2026, 8, 7));

      // 12:30 AM on Aug 8 -> Logical day Aug 7
      final t3 = DateTime(2026, 8, 8, 0, 30);
      expect(MedicationIntake.getLogicalDate(t3), DateTime(2026, 8, 7));

      // 03:59 AM on Aug 8 -> Logical day Aug 7
      final t4 = DateTime(2026, 8, 8, 3, 59);
      expect(MedicationIntake.getLogicalDate(t4), DateTime(2026, 8, 7));

      // 04:00 AM on Aug 8 -> Rollover to logical day Aug 8 (Morning!)
      final t5 = DateTime(2026, 8, 8, 4, 0);
      expect(MedicationIntake.getLogicalDate(t5), DateTime(2026, 8, 8));

      // 08:00 AM on Aug 8 -> Logical day Aug 8
      final t6 = DateTime(2026, 8, 8, 8, 0);
      expect(MedicationIntake.getLogicalDate(t6), DateTime(2026, 8, 8));
    });

    test('isForLogicalDate matches correctly across midnight', () {
      final quetiapine = Medication(
        medicationId: 'med_quetiapine',
        name: 'Quetiapine',
        dosage: 25.0,
        unit: DosageUnit.mg,
        color: '#9b59b6',
        icon: '🌙',
        createdAt: DateTime(2026, 1, 1),
      );

      final schedule = MedicationSchedule(
        scheduleId: 'sched_quetiapine',
        medication: quetiapine,
        startDate: DateTime(2026, 8, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 22, minute: 0)], // 10:00 PM
        createdAt: DateTime(2026, 8, 1),
      );

      final intakeAug7 = MedicationIntake(
        schedule: schedule,
        scheduledTime: DateTime(2026, 8, 7, 22, 0),
      );

      // Check against Aug 7 logical date
      expect(intakeAug7.isForLogicalDate(DateTime(2026, 8, 7)), isTrue);
      // Check from a test time of 12:30 AM on Aug 8
      final testTimeMidnight = DateTime(2026, 8, 8, 0, 30);
      final logicalAtMidnight = MedicationIntake.getLogicalDate(testTimeMidnight);
      expect(intakeAug7.isForLogicalDate(logicalAtMidnight), isTrue);
    });
  });

  group('Night Medication Grace Period & Due Now Evaluation', () {
    late Medication quetiapine;
    late MedicationSchedule nightSchedule;
    late MedicationIntake bedtimeIntake;

    setUp(() {
      quetiapine = Medication(
        medicationId: 'med_quetiapine',
        name: 'Quetiapine',
        dosage: 25.0,
        unit: DosageUnit.mg,
        color: '#9b59b6',
        icon: '🌙',
        createdAt: DateTime(2026, 1, 1),
      );

      nightSchedule = MedicationSchedule(
        scheduleId: 'sched_quetiapine',
        medication: quetiapine,
        startDate: DateTime(2026, 8, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 22, minute: 0)], // 10:00 PM
        createdAt: DateTime(2026, 8, 1),
      );

      bedtimeIntake = MedicationIntake(
        schedule: nightSchedule,
        scheduledTime: DateTime(2026, 8, 7, 22, 0),
      );
    });

    test('Identifies bedtime medication as isNightDose', () {
      expect(bedtimeIntake.isNightDose, isTrue);
    });

    test('Bedtime dose remains Due Now at 10 PM, 12:30 AM, and 2:00 AM', () {
      // 10:00 PM on Aug 7
      expect(bedtimeIntake.isDueNow(DateTime(2026, 8, 7, 22, 0)), isTrue);
      expect(bedtimeIntake.isOverdue(DateTime(2026, 8, 7, 22, 0)), isFalse);

      // 12:30 AM on Aug 8 (After midnight)
      expect(bedtimeIntake.isDueNow(DateTime(2026, 8, 8, 0, 30)), isTrue);
      expect(bedtimeIntake.isOverdue(DateTime(2026, 8, 8, 0, 30)), isFalse);

      // 02:00 AM on Aug 8 (Late night)
      expect(bedtimeIntake.isDueNow(DateTime(2026, 8, 8, 2, 0)), isTrue);
      expect(bedtimeIntake.isOverdue(DateTime(2026, 8, 8, 2, 0)), isFalse);

      // 03:59 AM on Aug 8 (Right before 4 AM rollover)
      expect(bedtimeIntake.isDueNow(DateTime(2026, 8, 8, 3, 59)), isTrue);
      expect(bedtimeIntake.isOverdue(DateTime(2026, 8, 8, 3, 59)), isFalse);
    });

    test('Bedtime dose expires to Overdue only after 4:00 AM rollover', () {
      // 04:01 AM on Aug 8
      expect(bedtimeIntake.isDueNow(DateTime(2026, 8, 8, 4, 1)), isFalse);
      expect(bedtimeIntake.isOverdue(DateTime(2026, 8, 8, 4, 1)), isTrue);
    });

    test('Logging bedtime dose at 12:30 AM marks it taken and records actual time', () {
      final logTime = DateTime(2026, 8, 8, 0, 30);
      final takenIntake = bedtimeIntake.markTaken(actualTime: logTime);

      expect(takenIntake.status, IntakeStatus.taken);
      expect(takenIntake.actualTime, logTime);
      expect(takenIntake.isDueNow(logTime), isFalse);
      expect(takenIntake.isOverdue(logTime), isFalse);
    });
  });

  group('Morning Medication (Sertraline) Lifecycle', () {
    late Medication sertraline;
    late MedicationSchedule morningSchedule;
    late MedicationIntake morningIntake;

    setUp(() {
      sertraline = Medication(
        medicationId: 'med_sertraline',
        name: 'Sertraline',
        dosage: 50.0,
        unit: DosageUnit.mg,
        color: '#3498db',
        icon: '☀️',
        createdAt: DateTime(2026, 1, 1),
      );

      morningSchedule = MedicationSchedule(
        scheduleId: 'sched_sertraline',
        medication: sertraline,
        startDate: DateTime(2026, 8, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 8, minute: 0)], // 8:00 AM
        createdAt: DateTime(2026, 8, 1),
      );

      morningIntake = MedicationIntake(
        schedule: morningSchedule,
        scheduledTime: DateTime(2026, 8, 8, 8, 0),
      );
    });

    test('Daytime medication properties', () {
      expect(morningIntake.isNightDose, isFalse);
    });

    test('Daytime dose is Due Now within window and Overdue 3 hours later', () {
      // 7:00 AM (too early)
      expect(morningIntake.isDueNow(DateTime(2026, 8, 8, 7, 0)), isFalse);

      // 7:45 AM (30 mins before)
      expect(morningIntake.isDueNow(DateTime(2026, 8, 8, 7, 45)), isTrue);

      // 8:00 AM (on time)
      expect(morningIntake.isDueNow(DateTime(2026, 8, 8, 8, 0)), isTrue);
      expect(morningIntake.isOverdue(DateTime(2026, 8, 8, 8, 0)), isFalse);

      // 10:30 AM (within 3 hour window)
      expect(morningIntake.isDueNow(DateTime(2026, 8, 8, 10, 30)), isTrue);
      expect(morningIntake.isOverdue(DateTime(2026, 8, 8, 10, 30)), isFalse);

      // 11:30 AM (after 3 hours -> Overdue)
      expect(morningIntake.isDueNow(DateTime(2026, 8, 8, 11, 30)), isFalse);
      expect(morningIntake.isOverdue(DateTime(2026, 8, 8, 11, 30)), isTrue);
    });
  });

  group('MedicationManager Service Circadian Logic', () {
    late MedicationManager manager;
    late Medication quetiapine;
    late Medication sertraline;

    setUp(() {
      manager = MedicationManager();

      quetiapine = Medication(
        medicationId: 'med_quetiapine',
        name: 'Quetiapine',
        dosage: 25.0,
        unit: DosageUnit.mg,
        color: '#9b59b6',
        icon: '🌙',
        createdAt: DateTime(2026, 1, 1),
      );

      sertraline = Medication(
        medicationId: 'med_sertraline',
        name: 'Sertraline',
        dosage: 50.0,
        unit: DosageUnit.mg,
        color: '#3498db',
        icon: '☀️',
        createdAt: DateTime(2026, 1, 1),
      );

      final scheduleNight = MedicationSchedule(
        scheduleId: 'sched_quetiapine',
        medication: quetiapine,
        startDate: DateTime(2026, 8, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 22, minute: 0)],
        createdAt: DateTime(2026, 8, 1),
      );

      final scheduleMorning = MedicationSchedule(
        scheduleId: 'sched_sertraline',
        medication: sertraline,
        startDate: DateTime(2026, 8, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [const TimeOfDay(hour: 8, minute: 0)],
        createdAt: DateTime(2026, 8, 1),
      );

      manager.addMedication(quetiapine);
      manager.addMedication(sertraline);
      manager.addSchedule(scheduleNight);
      manager.addSchedule(scheduleMorning);
    });

    test('getIntakesForDate at 12:30 AM returns both Sertraline and Quetiapine for that logical day', () {
      final midnightCheck = DateTime(2026, 8, 8, 0, 30);
      final intakes = manager.getIntakesForDate(midnightCheck);

      expect(intakes.length, 2);
      expect(intakes.any((i) => i.schedule.medication.name == 'Quetiapine'), isTrue);
      expect(intakes.any((i) => i.schedule.medication.name == 'Sertraline'), isTrue);
    });

    test('checkAndMarkMissedIntakes preserves night dose pending at 12:30 AM', () {
      manager.ensureIntakesForDate(DateTime(2026, 8, 7));

      // At 12:30 AM, Quetiapine from Aug 7 is still pending
      final quetiapineIntake = manager.allIntakes.firstWhere(
        (i) => i.schedule.medication.name == 'Quetiapine',
      );
      expect(quetiapineIntake.status, IntakeStatus.pending);

      // Missed check logic
      final testTime = DateTime(2026, 8, 8, 0, 30);
      expect(quetiapineIntake.isOverdue(testTime), isFalse);
    });

    test('Adherence percentage properly calculates when Quetiapine is taken at 12:30 AM', () {
      manager.ensureIntakesForDate(DateTime(2026, 8, 7));
      final intakes = manager.getIntakesForDate(DateTime(2026, 8, 7));
      expect(intakes.length, 2);

      // Take Sertraline at 8:15 AM
      final sertraline = intakes.firstWhere((i) => i.schedule.medication.name == 'Sertraline');
      manager.updateIntake(sertraline.markTaken(actualTime: DateTime(2026, 8, 7, 8, 15)));

      // Take Quetiapine at 12:30 AM (calendar next day)
      final quetiapine = intakes.firstWhere((i) => i.schedule.medication.name == 'Quetiapine');
      manager.updateIntake(quetiapine.markTaken(actualTime: DateTime(2026, 8, 8, 0, 30)));

      // Check adherence for logical day Aug 7
      final updatedIntakes = manager.getIntakesForDate(DateTime(2026, 8, 7));
      final takenCount = updatedIntakes.where((i) => i.status == IntakeStatus.taken).length;
      expect(takenCount, 2);
      expect(takenCount / updatedIntakes.length, 1.0); // 100% adherence!
    });
  });

  group('Overnight Schedule Generation & Cutoff Thresholds', () {
    test('Schedules with times before 4 AM are placed on the next calendar morning', () {
      final sleepAid = Medication(
        medicationId: 'med_sleep',
        name: 'Sleep Aid',
        dosage: 10.0,
        unit: DosageUnit.mg,
        color: '#2c3e50',
        icon: '💤',
        createdAt: DateTime(2026, 1, 1),
      );

      final scheduleOvernight = MedicationSchedule(
        scheduleId: 'sched_sleep',
        medication: sleepAid,
        startDate: DateTime(2026, 8, 1),
        frequency: MedicationFrequency.daily,
        timesPerDay: [
          const TimeOfDay(hour: 0, minute: 0),   // 12:00 AM Midnight
          const TimeOfDay(hour: 1, minute: 30),  // 01:30 AM
          const TimeOfDay(hour: 3, minute: 59),  // 03:59 AM
          const TimeOfDay(hour: 4, minute: 0),   // 04:00 AM (Day starts)
          const TimeOfDay(hour: 23, minute: 0),  // 11:00 PM
        ],
        createdAt: DateTime(2026, 8, 1),
      );

      final generated = scheduleOvernight.generateIntakesForDate(DateTime(2026, 8, 7));
      expect(generated.length, 5);

      // 12:00 AM -> Scheduled for Aug 8, 00:00
      final midnightIntake = generated.firstWhere((i) => i.scheduledTime.hour == 0);
      expect(midnightIntake.scheduledTime, DateTime(2026, 8, 8, 0, 0));
      expect(midnightIntake.logicalDate, DateTime(2026, 8, 7));

      // 1:30 AM -> Scheduled for Aug 8, 01:30
      final lateIntake = generated.firstWhere((i) => i.scheduledTime.hour == 1);
      expect(lateIntake.scheduledTime, DateTime(2026, 8, 8, 1, 30));
      expect(lateIntake.logicalDate, DateTime(2026, 8, 7));

      // 3:59 AM -> Scheduled for Aug 8, 03:59
      final preCutoff = generated.firstWhere((i) => i.scheduledTime.hour == 3);
      expect(preCutoff.scheduledTime, DateTime(2026, 8, 8, 3, 59));
      expect(preCutoff.logicalDate, DateTime(2026, 8, 7));

      // 4:00 AM -> Scheduled for Aug 7, 04:00 (Start of Aug 7 morning)
      final morningIntake = generated.firstWhere((i) => i.scheduledTime.hour == 4);
      expect(morningIntake.scheduledTime, DateTime(2026, 8, 7, 4, 0));
      expect(morningIntake.logicalDate, DateTime(2026, 8, 7));

      // 11:00 PM -> Scheduled for Aug 7, 23:00
      final eveningIntake = generated.firstWhere((i) => i.scheduledTime.hour == 23);
      expect(eveningIntake.scheduledTime, DateTime(2026, 8, 7, 23, 0));
      expect(eveningIntake.logicalDate, DateTime(2026, 8, 7));
    });
  });
}

