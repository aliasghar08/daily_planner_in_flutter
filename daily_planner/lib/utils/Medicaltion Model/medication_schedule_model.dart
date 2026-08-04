import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:flutter/material.dart';

class MedicationSchedule {
  final String scheduleId;
  final Medication medication;
  final DateTime startDate;
  final DateTime? endDate;
  final MedicationFrequency frequency;
  final List<TimeOfDay> timesPerDay;
  final List<int> daysOfWeek; // 0-6 for Monday-Sunday
  final List<DateTime> specificDates;
  final String? instructions;
  final int reminderMinutesBefore;
  final DateTime createdAt;

  MedicationSchedule({
    String? scheduleId,
    required this.medication,
    required this.startDate,
    this.endDate,
    this.frequency = MedicationFrequency.daily,
    this.timesPerDay = const [],
    this.daysOfWeek = const [],
    this.specificDates = const [],
    this.instructions,
    this.reminderMinutesBefore = 15,
    DateTime? createdAt,
  })  : scheduleId =
            scheduleId ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
        createdAt = createdAt ?? DateTime.now();

  MedicationSchedule copyWith({
    String? scheduleId,
    Medication? medication,
    DateTime? startDate,
    DateTime? endDate,
    MedicationFrequency? frequency,
    List<TimeOfDay>? timesPerDay,
    List<int>? daysOfWeek,
    List<DateTime>? specificDates,
    String? instructions,
    int? reminderMinutesBefore,
    DateTime? createdAt,
  }) {
    return MedicationSchedule(
      scheduleId: scheduleId ?? this.scheduleId,
      medication: medication ?? this.medication,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      frequency: frequency ?? this.frequency,
      timesPerDay: timesPerDay ?? this.timesPerDay,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      specificDates: specificDates ?? this.specificDates,
      instructions: instructions ?? this.instructions,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  List<MedicationIntake> generateIntakesForDate(DateTime date) {
    final List<MedicationIntake> intakes = [];

    // Normalize dates for comparison (remove time component)
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStartDate = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEndDate =
        endDate != null
            ? DateTime(endDate!.year, endDate!.month, endDate!.day)
            : null;

    // Check if date is within schedule range
    if (normalizedDate.isBefore(normalizedStartDate) ||
        (normalizedEndDate != null &&
            normalizedDate.isAfter(normalizedEndDate))) {
      return intakes;
    }

    // Check if date matches the schedule frequency
    if (!_isDateApplicable(date)) {
      return intakes;
    }

    // Generate intakes for each time of day
    for (final time in timesPerDay) {
      final scheduledTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      // Create a stable, deterministic ID based on scheduleId, date, and time
      final intakeId =
          'intake_${scheduleId}_${scheduledTime.year}_${scheduledTime.month}_${scheduledTime.day}_${scheduledTime.hour}_${scheduledTime.minute}';

      final intake = MedicationIntake(
        intakeId: intakeId,
        schedule: this,
        scheduledTime: scheduledTime,
        status: IntakeStatus.pending,
      );

      intakes.add(intake);
    }

    return intakes;
  }

  bool _isDateApplicable(DateTime date) {
    switch (frequency) {
      case MedicationFrequency.daily:
        return true;
      case MedicationFrequency.weekly:
        // DateTime.weekday: Monday is 1, Sunday is 7.
        // We use 0 for Monday to 6 for Sunday.
        return daysOfWeek.contains(date.weekday - 1);
      case MedicationFrequency.monthly:
        return date.day == startDate.day;
      case MedicationFrequency.asNeeded:
        return false;
      case MedicationFrequency.custom:
        return specificDates.any(
          (specificDate) =>
              specificDate.year == date.year &&
              specificDate.month == date.month &&
              specificDate.day == date.day,
        );
    }
  }

  List<MedicationIntake> generateIntakesForDateRange(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final List<MedicationIntake> intakes = [];
    DateTime currentDate = DateTime(
      rangeStart.year,
      rangeStart.month,
      rangeStart.day,
    );
    final lastDate = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    while (!currentDate.isAfter(lastDate)) {
      intakes.addAll(generateIntakesForDate(currentDate));
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return intakes;
  }

  Map<String, dynamic> toMap() {
    return {
      'scheduleId': scheduleId,
      'medicationId': medication.medicationId,
      'medication': medication.toMap(),
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'frequency': frequency.name,
      'timesPerDay':
          timesPerDay.map((time) => {'hour': time.hour, 'minute': time.minute}).toList(),
      'daysOfWeek': daysOfWeek,
      'specificDates':
          specificDates.map((date) => date.millisecondsSinceEpoch).toList(),
      'instructions': instructions,
      'reminderMinutesBefore': reminderMinutesBefore,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory MedicationSchedule.fromMap(Map<String, dynamic> map, [String? docId, Medication? fallbackMedication]) {
    DateTime parseDate(dynamic value, [DateTime? defaultVal]) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? (defaultVal ?? DateTime.now());
      return defaultVal ?? DateTime.now();
    }

    List<TimeOfDay> parseTimes(dynamic rawList) {
      if (rawList is! List) return [];
      final List<TimeOfDay> results = [];
      for (final item in rawList) {
        if (item is Map) {
          final h = (item['hour'] as num?)?.toInt() ?? 0;
          final m = (item['minute'] as num?)?.toInt() ?? 0;
          results.add(TimeOfDay(hour: h, minute: m));
        } else if (item is String) {
          final parts = item.split(':');
          if (parts.length == 2) {
            results.add(
              TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 0,
                minute: int.tryParse(parts[1]) ?? 0,
              ),
            );
          }
        }
      }
      return results;
    }

    List<int> parseDays(dynamic rawList) {
      if (rawList is! List) return [];
      return rawList.map((e) => (e as num).toInt()).toList();
    }

    List<DateTime> parseSpecificDates(dynamic rawList) {
      if (rawList is! List) return [];
      final List<DateTime> results = [];
      for (final item in rawList) {
        if (item is int) results.add(DateTime.fromMillisecondsSinceEpoch(item));
        if (item is Timestamp) results.add(item.toDate());
        if (item is String) {
          final dt = DateTime.tryParse(item);
          if (dt != null) results.add(dt);
        }
      }
      return results;
    }

    Medication med;
    if (map['medication'] is Map<String, dynamic>) {
      med = Medication.fromMap(map['medication'] as Map<String, dynamic>);
    } else if (fallbackMedication != null) {
      med = fallbackMedication;
    } else {
      med = Medication(
        medicationId: map['medicationId'] ?? 'unknown',
        name: map['medicationName'] ?? 'Medication',
        dosage: (map['dosage'] as num?)?.toDouble() ?? 0.0,
        unit: DosageUnit.tablet,
      );
    }

    return MedicationSchedule(
      scheduleId: docId ?? map['scheduleId'] ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
      medication: med,
      startDate: parseDate(map['startDate']),
      endDate: map['endDate'] != null ? parseDate(map['endDate']) : null,
      frequency: MedicationFrequency.values.firstWhere(
        (e) => e.name == map['frequency'],
        orElse: () => MedicationFrequency.daily,
      ),
      timesPerDay: parseTimes(map['timesPerDay']),
      daysOfWeek: parseDays(map['daysOfWeek']),
      specificDates: parseSpecificDates(map['specificDates']),
      instructions: map['instructions'],
      reminderMinutesBefore: (map['reminderMinutesBefore'] as num?)?.toInt() ?? 15,
      createdAt: parseDate(map['createdAt']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MedicationSchedule && other.scheduleId == scheduleId;
  }

  @override
  int get hashCode => scheduleId.hashCode;
}
