import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'custom_chart_models.dart';

/// A custom, animated, and interactive Pie / Donut Chart widget
class CustomPieChart extends StatefulWidget {
  final List<CustomPieSliceData> sections;
  final double centerSpaceRadius;
  final double sectionsSpace;
  final double startDegreeOffset;
  final Duration animationDuration;
  final Widget? centerWidget;
  final bool enableTouch;
  final ValueChanged<int?>? onSectionTouched;

  const CustomPieChart({
    super.key,
    required this.sections,
    this.centerSpaceRadius = 40.0,
    this.sectionsSpace = 2.0,
    this.startDegreeOffset = -90.0,
    this.animationDuration = const Duration(milliseconds: 800),
    this.centerWidget,
    this.enableTouch = true,
    this.onSectionTouched,
  });

  @override
  State<CustomPieChart> createState() => _CustomPieChartState();
}

class _CustomPieChartState extends State<CustomPieChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(CustomPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections != widget.sections) {
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTap(Offset localPosition, Size size) {
    if (!widget.enableTouch || widget.sections.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    final maxRadius = math.min(size.width, size.height) / 2;
    if (distance < widget.centerSpaceRadius || distance > maxRadius) {
      setState(() => _touchedIndex = null);
      widget.onSectionTouched?.call(null);
      return;
    }

    var angle = math.atan2(dy, dx) * 180 / math.pi;
    angle = (angle - widget.startDegreeOffset) % 360;
    if (angle < 0) angle += 360;

    final totalValue = widget.sections.fold<double>(
      0.0,
      (sum, item) => sum + item.value,
    );
    if (totalValue <= 0) return;

    double currentAngle = 0;
    int? foundIndex;

    for (int i = 0; i < widget.sections.length; i++) {
      final sweepAngle = (widget.sections[i].value / totalValue) * 360;
      if (angle >= currentAngle && angle <= currentAngle + sweepAngle) {
        foundIndex = i;
        break;
      }
      currentAngle += sweepAngle;
    }

    setState(() => _touchedIndex = foundIndex);
    widget.onSectionTouched?.call(foundIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      return const Center(child: Text("No chart data"));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : math.min(width, 220.0);
        final size = Size(width, height);

        return GestureDetector(
          onTapDown: (details) => _handleTap(details.localPosition, size),
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: size,
                    painter: _PieChartPainter(
                      sections: widget.sections,
                      progress: _animation.value,
                      centerSpaceRadius: widget.centerSpaceRadius,
                      sectionsSpace: widget.sectionsSpace,
                      startDegreeOffset: widget.startDegreeOffset,
                      touchedIndex: _touchedIndex,
                    ),
                  ),
                  if (widget.centerWidget != null)
                    Center(child: widget.centerWidget),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<CustomPieSliceData> sections;
  final double progress;
  final double centerSpaceRadius;
  final double sectionsSpace;
  final double startDegreeOffset;
  final int? touchedIndex;

  _PieChartPainter({
    required this.sections,
    required this.progress,
    required this.centerSpaceRadius,
    required this.sectionsSpace,
    required this.startDegreeOffset,
    this.touchedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxAvailableRadius = math.min(size.width, size.height) / 2;

    final totalValue = sections.fold<double>(
      0.0,
      (sum, item) => sum + item.value,
    );
    if (totalValue <= 0) return;

    double currentAngleRad = startDegreeOffset * (math.pi / 180);
    final spaceRad = (sections.length > 1 ? sectionsSpace : 0.0) * (math.pi / 180);

    for (int i = 0; i < sections.length; i++) {
      final section = sections[i];
      final sweepAngleTotal = (section.value / totalValue) * 2 * math.pi;
      final sweepAngle = (sweepAngleTotal * progress) - spaceRad;

      if (sweepAngle > 0) {
        final isTouched = touchedIndex == i;
        final extraRadius = isTouched ? 6.0 : 0.0;
        final sectionThickness = (section.radius > 0 ? section.radius : 45.0) + extraRadius;

        final paint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = sectionThickness
          ..color = section.color;

        final arcRadius = math.min(
          centerSpaceRadius + (sectionThickness / 2),
          maxAvailableRadius - (extraRadius / 2),
        );

        final rect = Rect.fromCircle(center: center, radius: arcRadius);
        canvas.drawArc(
          rect,
          currentAngleRad + (spaceRad / 2),
          sweepAngle,
          false,
          paint,
        );

        // Draw title text
        if (section.title.isNotEmpty && progress > 0.6) {
          final midAngle = currentAngleRad + (sweepAngle / 2);
          final textRadius = arcRadius;
          final textCenter = Offset(
            center.dx + textRadius * math.cos(midAngle),
            center.dy + textRadius * math.sin(midAngle),
          );

          final textSpan = TextSpan(
            text: section.title,
            style: section.titleStyle ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black45, blurRadius: 3),
                  ],
                ),
          );

          final textPainter = TextPainter(
            text: textSpan,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          )..layout();

          final textOffset = Offset(
            textCenter.dx - (textPainter.width / 2),
            textCenter.dy - (textPainter.height / 2),
          );

          textPainter.paint(canvas, textOffset);
        }
      }

      currentAngleRad += sweepAngleTotal * progress;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.touchedIndex != touchedIndex ||
        oldDelegate.sections != sections;
  }
}
