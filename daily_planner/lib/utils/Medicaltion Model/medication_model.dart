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
  }) : medicationId =
           medicationId ?? 'med_${DateTime.now().millisecondsSinceEpoch}',
       createdAt = createdAt ?? DateTime.now();

  Medication copyWith({
    String? name,
    double? dosage,
    DosageUnit? unit,
    String? description,
    String? color,
    String? icon,
    bool? isActive,
  }) {
    return Medication(
      medicationId: medicationId,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt,
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
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isActive': isActive,
    };
  }

  factory Medication.fromMap(Map<String, dynamic> map) {
    return Medication(
      medicationId: map['medicationId'],
      name: map['name'],
      dosage: map['dosage']?.toDouble(),
      unit: DosageUnit.values.firstWhere(
        (e) => e.name == map['unit'],
        orElse: () => DosageUnit.tablet,
      ),
      description: map['description'],
      color: map['color'] ?? '#3498db',
      icon: map['icon'] ?? '💊',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
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
