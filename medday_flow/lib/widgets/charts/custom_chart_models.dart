import 'package:flutter/material.dart';

/// Data class representing a slice in [CustomPieChart]
class CustomPieSliceData {
  final double value;
  final Color color;
  final String title;
  final double radius;
  final TextStyle? titleStyle;
  final Widget? badge;

  const CustomPieSliceData({
    required this.value,
    required this.color,
    this.title = '',
    this.radius = 50.0,
    this.titleStyle,
    this.badge,
  });
}

/// Data class representing a single bar rod in a bar chart group
class CustomBarRodData {
  final double toY;
  final Color color;
  final double width;
  final BorderRadius? borderRadius;
  final Gradient? gradient;
  final String? tooltip;

  const CustomBarRodData({
    required this.toY,
    this.color = Colors.blueAccent,
    this.width = 18.0,
    this.borderRadius,
    this.gradient,
    this.tooltip,
  });
}

/// Data class representing a group of bar rods at an x index
class CustomBarGroupData {
  final int x;
  final List<CustomBarRodData> barRods;
  final String? label;

  const CustomBarGroupData({
    required this.x,
    required this.barRods,
    this.label,
  });
}
