import 'package:cloud_firestore/cloud_firestore.dart';
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

  static String generateIntakeId(String scheduleId, DateTime time) {
    final m = time.minute.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '${scheduleId}_${time.year}-$mo-${d}_$h$m';
  }

  MedicationIntake({
    String? intakeId,
    required this.schedule,
    required this.scheduledTime,
    this.actualTime,
    this.status = IntakeStatus.pending,
    this.notes,
    this.dosageTaken,
  }) : intakeId = intakeId ?? generateIntakeId(schedule.scheduleId, scheduledTime);

  MedicationIntake copyWith({
    String? intakeId,
    MedicationSchedule? schedule,
    DateTime? scheduledTime,
    DateTime? actualTime,
    IntakeStatus? status,
    String? notes,
    double? dosageTaken,
  }) {
    return MedicationIntake(
      intakeId: intakeId ?? this.intakeId,
      schedule: schedule ?? this.schedule,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      actualTime: actualTime ?? this.actualTime,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      dosageTaken: dosageTaken ?? this.dosageTaken,
    );
  }

  MedicationIntake markTaken({DateTime? actualTime, String? notes}) {
    return MedicationIntake(
      intakeId: intakeId,
      schedule: schedule,
      scheduledTime: scheduledTime,
      actualTime: actualTime ?? DateTime.now(),
      status: IntakeStatus.taken,
      notes: notes ?? this.notes,
      dosageTaken: schedule.medication.dosage,
    );
  }

  MedicationIntake markMissed({String? notes}) {
    return MedicationIntake(
      intakeId: intakeId,
      schedule: schedule,
      scheduledTime: scheduledTime,
      actualTime: actualTime,
      status: IntakeStatus.missed,
      notes: notes ?? this.notes,
      dosageTaken: dosageTaken,
    );
  }

  MedicationIntake markSkipped({String? notes}) {
    return MedicationIntake(
      intakeId: intakeId,
      schedule: schedule,
      scheduledTime: scheduledTime,
      actualTime: actualTime,
      status: IntakeStatus.skipped,
      notes: notes ?? this.notes,
      dosageTaken: dosageTaken,
    );
  }

  bool get isForToday {
    final now = DateTime.now();
    return scheduledTime.year == now.year &&
        scheduledTime.month == now.month &&
        scheduledTime.day == now.day;
  }

  bool get isUpcoming {
    final now = DateTime.now();
    final oneHourFromNow = now.add(const Duration(hours: 1));
    return scheduledTime.isAfter(now) && scheduledTime.isBefore(oneHourFromNow);
  }

  Map<String, dynamic> toMap() {
    return {
      'intakeId': intakeId,
      'scheduleId': schedule.scheduleId,
      'medicationId': schedule.medication.medicationId,
      'schedule': schedule.toMap(),
      'scheduledTime': scheduledTime.millisecondsSinceEpoch,
      'actualTime': actualTime?.millisecondsSinceEpoch,
      'status': status.name,
      'notes': notes,
      'dosageTaken': dosageTaken,
    };
  }

  factory MedicationIntake.fromMap(
    Map<String, dynamic> map, [
    String? docId,
    MedicationSchedule? fallbackSchedule,
  ]) {
    DateTime parseDate(dynamic value, [DateTime? defaultVal]) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? (defaultVal ?? DateTime.now());
      return defaultVal ?? DateTime.now();
    }

    MedicationSchedule sched;
    if (map['schedule'] is Map<String, dynamic>) {
      sched = MedicationSchedule.fromMap(map['schedule'] as Map<String, dynamic>);
    } else if (fallbackSchedule != null) {
      sched = fallbackSchedule;
    } else {
      throw Exception('Schedule missing in MedicationIntake.fromMap');
    }

    return MedicationIntake(
      intakeId: docId ?? map['intakeId'] ?? 'intake_${DateTime.now().millisecondsSinceEpoch}',
      schedule: sched,
      scheduledTime: parseDate(map['scheduledTime']),
      actualTime: map['actualTime'] != null ? parseDate(map['actualTime']) : null,
      status: IntakeStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => IntakeStatus.pending,
      ),
      notes: map['notes'],
      dosageTaken: (map['dosageTaken'] as num?)?.toDouble(),
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