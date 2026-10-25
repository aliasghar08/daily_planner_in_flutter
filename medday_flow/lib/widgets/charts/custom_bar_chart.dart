import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'custom_chart_models.dart';

/// Function signature for building bottom axis title widgets
typedef BottomTitleWidgetBuilder = Widget Function(int index, String label);

/// A custom, animated, and interactive Bar Chart widget
class CustomBarChart extends StatefulWidget {
  final List<CustomBarGroupData> barGroups;
  final double? maxY;
  final double? minY;
  final bool showGrid;
  final Color gridColor;
  final Duration animationDuration;
  final BottomTitleWidgetBuilder? bottomTitleBuilder;
  final bool enableTouch;
  final ValueChanged<int?>? onBarTouched;

  const CustomBarChart({
    super.key,
    required this.barGroups,
    this.maxY,
    this.minY = 0.0,
    this.showGrid = false,
    this.gridColor = const Color(0x1F000000),
    this.animationDuration = const Duration(milliseconds: 700),
    this.bottomTitleBuilder,
    this.enableTouch = true,
    this.onBarTouched,
  });

  @override
  State<CustomBarChart> createState() => _CustomBarChartState();
}

class _CustomBarChartState extends State<CustomBarChart>
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
  void didUpdateWidget(CustomBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barGroups != widget.barGroups) {
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double _calculateMaxY() {
    if (widget.maxY != null && widget.maxY! > 0) return widget.maxY!;
    double maxVal = 1.0;
    for (final group in widget.barGroups) {
      for (final rod in group.barRods) {
        if (rod.toY > maxVal) maxVal = rod.toY;
      }
    }
    return maxVal.ceilToDouble();
  }

  void _handleTap(Offset localPosition, double chartWidth, double chartHeight) {
    if (!widget.enableTouch || widget.barGroups.isEmpty) return;

    final count = widget.barGroups.length;
    final groupSlotWidth = chartWidth / count;
    final tappedIndex = (localPosition.dx / groupSlotWidth).floor();

    if (tappedIndex >= 0 && tappedIndex < count) {
      setState(() {
        _touchedIndex = (_touchedIndex == tappedIndex) ? null : tappedIndex;
      });
      widget.onBarTouched?.call(_touchedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.barGroups.isEmpty) {
      return const Center(child: Text("No data for chart"));
    }

    final computedMaxY = _calculateMaxY();

    return LayoutBuilder(
      builder: (context, constraints) {
        const bottomTitleReservedHeight = 32.0;
        final totalWidth = constraints.maxWidth;
        final totalHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 220.0;
        final chartDrawHeight = math.max(10.0, totalHeight - bottomTitleReservedHeight);

        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTapDown: (details) => _handleTap(
                  details.localPosition,
                  totalWidth,
                  chartDrawHeight,
                ),
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return CustomPaint(
                      size: Size(totalWidth, chartDrawHeight),
                      painter: _BarChartPainter(
                        barGroups: widget.barGroups,
                        progress: _animation.value,
                        maxY: computedMaxY,
                        minY: widget.minY ?? 0.0,
                        showGrid: widget.showGrid,
                        gridColor: widget.gridColor,
                        touchedIndex: _touchedIndex,
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              height: bottomTitleReservedHeight,
              child: Row(
                children: List.generate(widget.barGroups.length, (index) {
                  final group = widget.barGroups[index];
                  final label = group.label ?? index.toString();
                  return Expanded(
                    child: widget.bottomTitleBuilder != null
                        ? widget.bottomTitleBuilder!(index, label)
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<CustomBarGroupData> barGroups;
  final double progress;
  final double maxY;
  final double minY;
  final bool showGrid;
  final Color gridColor;
  final int? touchedIndex;

  _BarChartPainter({
    required this.barGroups,
    required this.progress,
    required this.maxY,
    required this.minY,
    required this.showGrid,
    required this.gridColor,
    this.touchedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barGroups.isEmpty || size.height <= 0 || size.width <= 0) return;

    // Draw background grid lines if enabled
    if (showGrid) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      const gridLines = 4;
      for (int i = 0; i <= gridLines; i++) {
        final y = size.height * (i / gridLines);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    final groupCount = barGroups.length;
    final slotWidth = size.width / groupCount;
    final valueRange = math.max(1.0, maxY - minY);

    for (int g = 0; g < groupCount; g++) {
      final group = barGroups[g];
      final groupCenterX = (g * slotWidth) + (slotWidth / 2);
      final isGroupTouched = touchedIndex == g;

      final rodCount = group.barRods.length;
      if (rodCount == 0) continue;

      const interRodSpacing = 2.0;
      final totalRodsWidth = group.barRods.fold<double>(
        0.0,
        (sum, r) => sum + math.min(r.width, (slotWidth / rodCount) - 1),
      ) + (interRodSpacing * (rodCount - 1));

      double currentRodLeft = groupCenterX - (totalRodsWidth / 2);

      for (int r = 0; r < rodCount; r++) {
        final rod = group.barRods[r];
        final effectiveWidth = math.min(rod.width, (slotWidth / rodCount) - 1);
        final rodWidth = isGroupTouched ? effectiveWidth + 2.0 : effectiveWidth;
        final targetHeight = ((rod.toY - minY) / valueRange) * size.height;
        final currentBarHeight = math.max(0.0, targetHeight * progress);

        final left = currentRodLeft;
        final top = size.height - currentBarHeight;
        final right = left + rodWidth;
        final bottom = size.height;

        final rect = Rect.fromLTRB(left, top, right, bottom);
        final radius = rod.borderRadius ?? BorderRadius.circular(4.0);
        final rrect = RRect.fromRectAndCorners(
          rect,
          topLeft: radius.topLeft,
          topRight: radius.topRight,
          bottomLeft: radius.bottomLeft,
          bottomRight: radius.bottomRight,
        );

        final paint = Paint()..isAntiAlias = true;
        if (rod.gradient != null) {
          paint.shader = rod.gradient!.createShader(rect);
        } else {
          paint.color = isGroupTouched
              ? rod.color.withValues(alpha: 0.85)
              : rod.color;
        }

        canvas.drawRRect(rrect, paint);

        // Draw tooltip / value indicator if touched
        if (isGroupTouched && progress > 0.8 && rod.toY > 0) {
          final tooltipVal = rod.toY.toInt().toString();
          final textSpan = TextSpan(
            text: tooltipVal,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          );

          final textPainter = TextPainter(
            text: textSpan,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          )..layout();

          final bubbleWidth = textPainter.width + 8;
          final bubbleHeight = textPainter.height + 4;
          final bubbleLeft = left + (rodWidth / 2) - (bubbleWidth / 2);
          final bubbleTop = math.max(0.0, top - bubbleHeight - 4);

          final bubbleRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleWidth, bubbleHeight),
            const Radius.circular(4),
          );

          final bubblePaint = Paint()..color = Colors.black87;
          canvas.drawRRect(bubbleRRect, bubblePaint);

          textPainter.paint(
            canvas,
            Offset(bubbleLeft + 4, bubbleTop + 2),
          );
        }

        currentRodLeft += rodWidth + interRodSpacing;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.touchedIndex != touchedIndex ||
        oldDelegate.barGroups != barGroups ||
        oldDelegate.maxY != maxY;
  }
}
