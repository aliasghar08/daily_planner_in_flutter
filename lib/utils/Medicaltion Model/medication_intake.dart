// lib/models/medication_intake.dart

import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';

import 'package:flutter/foundation.dart';

@immutable
class MedicationIntake {
  final String intakeId;
  final MedicationSchedule schedule;
  final DateTime scheduledTime;
  final DateTime? actualTime;
  final IntakeStatus status;
  final String? notes;
  final double? dosageTaken;

  // Remove 'const' from constructor since we have runtime values
  MedicationIntake({
    String? intakeId,
    required this.schedule,
    required this.scheduledTime,
    this.actualTime,
    this.status = IntakeStatus.pending,
    this.notes,
    this.dosageTaken,
  }) : intakeId = intakeId ?? 'intake_${DateTime.now().millisecondsSinceEpoch}';

  MedicationIntake markTaken({DateTime? actualTime, String? notes}) {
    return MedicationIntake(
      intakeId: intakeId, // Preserve the original ID
      schedule: schedule,
      scheduledTime: scheduledTime,
      actualTime: actualTime ?? DateTime.now(),
      status: IntakeStatus.taken,
      notes: notes,
      dosageTaken: schedule.medication.dosage,
    );
  }

  MedicationIntake markMissed({String? notes}) {
    return MedicationIntake(
      intakeId: intakeId, // Preserve the original ID
      schedule: schedule,
      scheduledTime: scheduledTime,
      actualTime: actualTime,
      status: IntakeStatus.missed,
      notes: notes,
      dosageTaken: dosageTaken,
    );
  }

  MedicationIntake markSkipped({String? notes}) {
    return MedicationIntake(
      intakeId: intakeId, // Preserve the original ID
      schedule: schedule,
      scheduledTime: scheduledTime,
      actualTime: actualTime,
      status: IntakeStatus.skipped,
      notes: notes,
      dosageTaken: dosageTaken,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'intakeId': intakeId,
      'schedule': schedule.toMap(),
      'scheduledTime': scheduledTime.millisecondsSinceEpoch,
      'actualTime': actualTime?.millisecondsSinceEpoch,
      'status': status.name,
      'notes': notes,
      'dosageTaken': dosageTaken,
    };
  }

  factory MedicationIntake.fromMap(Map<String, dynamic> map) {
    return MedicationIntake(
      intakeId: map['intakeId'],
      schedule: MedicationSchedule.fromMap(map['schedule']),
      scheduledTime: DateTime.fromMillisecondsSinceEpoch(map['scheduledTime']),
      actualTime:
          map['actualTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['actualTime'])
              : null,
      status: IntakeStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => IntakeStatus.pending,
      ),
      notes: map['notes'],
      dosageTaken: map['dosageTaken']?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MedicationIntake && other.intakeId == intakeId;
  }

  @override
  int get hashCode => intakeId.hashCode;
}
