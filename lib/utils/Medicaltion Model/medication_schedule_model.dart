// lib/models/medication_schedule.dart

import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:flutter/foundation.dart';
import 'package:daily_planner/utils/Medicaltion Model/frequency_and_dosage.dart';
import 'package:flutter/material.dart';

@immutable
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
  }) : scheduleId =
           scheduleId ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
       createdAt = createdAt ?? DateTime.now();

  void addDailySchedule(List<TimeOfDay> times) {
    timesPerDay
      ..clear()
      ..addAll(times..sort((a, b) => a.hour.compareTo(b.hour)));
    daysOfWeek
      ..clear()
      ..addAll([0, 1, 2, 3, 4, 5, 6]); // All days
  }

  void addWeeklySchedule(List<int> days, List<TimeOfDay> times) {
    timesPerDay
      ..clear()
      ..addAll(times..sort((a, b) => a.hour.compareTo(b.hour)));
    daysOfWeek
      ..clear()
      ..addAll(days);
  }

  void addCustomSchedule(List<DateTime> dates, List<TimeOfDay> times) {
    timesPerDay
      ..clear()
      ..addAll(times..sort((a, b) => a.hour.compareTo(b.hour)));
    specificDates
      ..clear()
      ..addAll(dates..sort((a, b) => a.compareTo(b)));
  }

  Map<String, dynamic> toMap() {
    return {
      'scheduleId': scheduleId,
      'medication': medication.toMap(),
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'frequency': frequency.name,
      'timesPerDay':
          timesPerDay.map((time) => '${time.hour}:${time.minute}').toList(),
      'daysOfWeek': daysOfWeek,
      'specificDates':
          specificDates.map((date) => date.millisecondsSinceEpoch).toList(),
      'instructions': instructions,
      'reminderMinutesBefore': reminderMinutesBefore,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory MedicationSchedule.fromMap(Map<String, dynamic> map) {
    return MedicationSchedule(
      scheduleId: map['scheduleId'],
      medication: Medication.fromMap(map['medication']),
      startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate']),
      endDate:
          map['endDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['endDate'])
              : null,
      frequency: MedicationFrequency.values.firstWhere(
        (e) => e.name == map['frequency'],
        orElse: () => MedicationFrequency.daily,
      ),
      timesPerDay:
          (map['timesPerDay'] as List)
              .map((timeStr) {
                final parts = timeStr.split(':');
                return TimeOfDay(
                  hour: int.parse(parts[0]),
                  minute: int.parse(parts[1]),
                );
              })
              .toList()
              .cast<TimeOfDay>(),
      daysOfWeek: (map['daysOfWeek'] as List).cast<int>(),
      specificDates:
          (map['specificDates'] as List)
              .map(
                (timestamp) => DateTime.fromMillisecondsSinceEpoch(timestamp),
              )
              .toList()
              .cast<DateTime>(),
      instructions: map['instructions'],
      reminderMinutesBefore: map['reminderMinutesBefore'] ?? 15,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
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
