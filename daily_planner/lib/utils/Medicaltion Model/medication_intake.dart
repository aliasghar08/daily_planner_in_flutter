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

  static const int defaultCircadianCutoffHour = 4;

  /// Returns the circadian "logical date" for a given DateTime.
  /// Any time between 00:00 and 03:59 AM is treated as part of the previous day's night/bedtime cycle.
  /// From 04:00 AM onwards, it is treated as the current calendar day.
  static DateTime getLogicalDate(DateTime dt, {int cutoffHour = defaultCircadianCutoffHour}) {
    // If dt has no time component (it's exactly midnight down to microseconds), 
    // it usually represents a purely logical calendar date selected from UI, 
    // rather than an actual wall-clock time that happened to be precisely midnight.
    if (dt.hour == 0 && dt.minute == 0 && dt.second == 0 && dt.millisecond == 0 && dt.microsecond == 0) {
      return DateTime(dt.year, dt.month, dt.day);
    }
    
    if (dt.hour < cutoffHour) {
      final prev = dt.subtract(const Duration(days: 1));
      return DateTime(prev.year, prev.month, prev.day);
    }
    return DateTime(dt.year, dt.month, dt.day);
  }

  static String generateIntakeId(String scheduleId, DateTime time) {
    return 'intake_${scheduleId}_${time.year}_${time.month}_${time.day}_${time.hour}_${time.minute}';
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

  /// Logical date this intake belongs to under the circadian 4:00 AM model
  DateTime get logicalDate => getLogicalDate(scheduledTime);

  /// Whether this intake belongs to the given logical date
  bool isForLogicalDate(DateTime targetLogicalDate, {int cutoffHour = defaultCircadianCutoffHour}) {
    final myLogical = getLogicalDate(scheduledTime, cutoffHour: cutoffHour);
    final target = DateTime(targetLogicalDate.year, targetLogicalDate.month, targetLogicalDate.day);
    return myLogical.year == target.year &&
        myLogical.month == target.month &&
        myLogical.day == target.day;
  }

  /// Deprecated helper, kept for compatibility. Prefer `isForLogicalDate(MedicationIntake.getLogicalDate(DateTime.now()))`
  bool get isForToday {
    final currentLogicalToday = getLogicalDate(DateTime.now());
    return isForLogicalDate(currentLogicalToday);
  }

  /// Whether this medication is scheduled during the Night / Bedtime window (9 PM - 4:59 AM)
  bool get isNightDose {
    final h = scheduledTime.hour;
    return h >= 21 || h < 5;
  }

  /// Checks if this intake is actively "Due Now" relative to a reference time (defaults to DateTime.now())
  /// - Bedtime / Night doses remain "Due Now" throughout the night (9:00 PM until 4:00 AM)
  /// - Daytime doses are "Due Now" from 30 mins before scheduled time up to 3 hours after
  bool isDueNow([DateTime? relativeTo]) {
    if (status != IntakeStatus.pending) return false;
    final now = relativeTo ?? DateTime.now();

    if (isNightDose) {
      // If it's for the active night cycle (between 9 PM evening and 4 AM next morning)
      final intakeLogical = logicalDate;
      final currentLogical = getLogicalDate(now);
      if (intakeLogical == currentLogical) {
        // If current hour is >= 20 or < 4, it's bedtime window
        final h = now.hour;
        if (h >= 20 || h < 4) return true;
        // Or if within 2 hours of scheduled time
        return now.isAfter(scheduledTime.subtract(const Duration(minutes: 30))) &&
            now.isBefore(scheduledTime.add(const Duration(hours: 4)));
      }
      return false;
    } else {
      // Daytime dose
      final windowStart = scheduledTime.subtract(const Duration(minutes: 30));
      final windowEnd = scheduledTime.add(const Duration(hours: 3));
      return now.isAfter(windowStart) && now.isBefore(windowEnd);
    }
  }

  /// Checks if the intake has passed its grace period without being taken
  bool isOverdue([DateTime? relativeTo]) {
    if (status != IntakeStatus.pending) return false;
    final now = relativeTo ?? DateTime.now();

    if (isNightDose) {
      // Night dose becomes overdue once the circadian day ends (past 4:00 AM next morning)
      final intakeLogical = logicalDate;
      final currentLogical = getLogicalDate(now);
      return currentLogical.isAfter(intakeLogical);
    } else {
      // Daytime dose is overdue 3 hours past scheduled time
      return now.isAfter(scheduledTime.add(const Duration(hours: 3)));
    }
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