import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:flutter/foundation.dart';

@immutable
class Medication {
  final String medicationId;
  final String name;
  final double dosage;
  final DosageUnit unit;
  final String? description;
  final String color;
  final String icon;
  final DateTime createdAt;
  final bool isActive;

  Medication({
    String? medicationId,
    required this.name,
    required this.dosage,
    required this.unit,
    this.description,
    this.color = '#3498db',
    this.icon = '💊',
    DateTime? createdAt,
    this.isActive = true,
  })  : medicationId =
            medicationId ?? 'med_${DateTime.now().millisecondsSinceEpoch}',
        createdAt = createdAt ?? DateTime.now();

  Medication copyWith({
    String? medicationId,
    String? name,
    double? dosage,
    DosageUnit? unit,
    String? description,
    String? color,
    String? icon,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Medication(
      medicationId: medicationId ?? this.medicationId,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'medicationId': medicationId,
      'name': name,
      'dosage': dosage,
      'unit': unit.name,
      'description': description,
      'color': color,
      'icon': icon,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
      'isActive': isActive,
    };
  }

  factory Medication.fromMap(Map<String, dynamic> map, [String? docId]) {
    DateTime parseCreatedAt(dynamic value) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return Medication(
      medicationId: docId ?? map['medicationId'] ?? 'med_${DateTime.now().millisecondsSinceEpoch}',
      name: map['name'] ?? '',
      dosage: (map['dosage'] as num?)?.toDouble() ?? 0.0,
      unit: DosageUnit.values.firstWhere(
        (e) => e.name == map['unit'],
        orElse: () => DosageUnit.tablet,
      ),
      description: map['description'],
      color: map['color'] ?? '#3498db',
      icon: map['icon'] ?? '💊',
      createdAt: parseCreatedAt(map['createdAt']),
      isActive: map['isActive'] ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Medication && other.medicationId == medicationId;
  }

  @override
  int get hashCode => medicationId.hashCode;
}
