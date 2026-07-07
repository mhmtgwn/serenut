// lib/presentation/widgets/revenue_bar_chart.dart
// Phase 2.3 — Custom Canvas Bar Chart
// Zero external dependencies — pure Flutter CustomPainter
// Generated: 21 Jun 2026

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:intl/intl.dart';

class RevenueBarChart extends StatefulWidget {
  final List<DailyRevenue> data;
  final double height;
  final Color barColor;
  final Color debtBarColor;

  const RevenueBarChart({
    super.key,
    required this.data,
    this.height = 200,
    this.barColor = const Color(0xFF16A34A),
    this.debtBarColor = const Color(0xFFEAB308),
  });

  @override
  State<RevenueBarChart> createState() => _RevenueBarChartState();
}

class _RevenueBarChartState extends State<RevenueBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _animation;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void didUpdateWidget(RevenueBarChart old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) {
      _animCtrl.reset();
      _animCtrl.forward();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text('Veri yok', style: TextStyle(color: Colors.grey[500])),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return SizedBox(
          height: widget.height + 40, // extra for labels
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details.localPosition),
            child: MouseRegion(
              onHover: (event) => _handleHover(event.localPosition),
              onExit: (_) => setState(() => _hoveredIndex = null),
              child: CustomPaint(
                painter: _BarChartPainter(
                  data: widget.data,
                  progress: _animation.value,
                  hoveredIndex: _hoveredIndex,
                  barColor: widget.barColor,
                  debtBarColor: widget.debtBarColor,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset position) {
    // Could open tooltip / detail
  }

  void _handleHover(Offset position) {
    if (!mounted) return;
    final barCount = widget.data.length;
    if (barCount == 0) return;

    // Approximate: find which bar was hovered
    // The painter uses the full width minus some padding
    const leftPad = 48.0;
    const rightPad = 8.0;
    final availW = context.size!.width - leftPad - rightPad;
    final barW = availW / barCount;
    final idx = ((position.dx - leftPad) / barW).floor();
    if (idx >= 0 && idx < barCount) {
      setState(() => _hoveredIndex = idx);
    } else {
      setState(() => _hoveredIndex = null);
    }
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailyRevenue> data;
  final double progress;
  final int? hoveredIndex;
  final Color barColor;
  final Color debtBarColor;

  _BarChartPainter({
    required this.data,
    required this.progress,
    required this.hoveredIndex,
    required this.barColor,
    required this.debtBarColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double leftPad = 48;
    const double rightPad = 8;
    const double bottomPad = 36;
    const double topPad = 12;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - bottomPad - topPad;

    final maxVal = data.fold<double>(
      0.0,
      (m, r) => math.max(m, r.totalAmount),
    );
    if (maxVal == 0) return;

    final barCount = data.length;
    final groupW = chartW / barCount;
    const barGap = 4.0;
    final barW = (groupW - barGap * 2).clamp(4.0, 48.0);

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;

    // Draw horizontal grid lines (4 lines)
    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH - (chartH * i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);

      // Y-axis labels
      final val = maxVal * i / 4;
      final label = _formatAmount(val);
      final tp = _buildTextPainter(label, 9, Colors.grey.shade500);
      tp.layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // X-axis line
    canvas.drawLine(
      Offset(leftPad, topPad + chartH),
      Offset(size.width - rightPad, topPad + chartH),
      axisPaint,
    );

    final barPaint = Paint()..style = PaintingStyle.fill;
    final debtPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = debtBarColor.withAlpha(204);

    for (int i = 0; i < barCount; i++) {
      final item = data[i];
      final x = leftPad + groupW * i + barGap;
      final barHeight = (item.totalAmount / maxVal) * chartH * progress;
      final debtHeight = (item.debtAmount / maxVal) * chartH * progress;
      final barTop = topPad + chartH - barHeight;

      final isHovered = hoveredIndex == i;

      // Main bar (cash portion)
      barPaint.color = isHovered
          ? barColor
          : barColor.withAlpha(204);

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, barTop, barW, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(barRect, barPaint);

      // Debt overlay on top of bar
      if (debtHeight > 0 && item.totalAmount > 0) {
        final debtRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, barTop, barW, math.min(debtHeight, barHeight)),
          const Radius.circular(3),
        );
        canvas.drawRRect(debtRect, debtPaint);
      }

      // X-axis label (date)
      final dateLabel = barCount <= 10
          ? DateFormat('dd.MM').format(item.date)
          : barCount <= 31
              ? (i % 5 == 0 ? DateFormat('dd').format(item.date) : '')
              : (i % 7 == 0 ? DateFormat('dd.MM').format(item.date) : '');
      if (dateLabel.isNotEmpty) {
        final tp = _buildTextPainter(dateLabel, 9, Colors.grey.shade500);
        tp.layout();
        tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, topPad + chartH + 4));
      }

      // Hover tooltip
      if (isHovered) {
        final tooltip = '${_formatAmount(item.totalAmount)} TL\n${item.saleCount} satış';
        final tp = _buildTextPainter(tooltip, 10, Colors.white, bold: true);
        tp.layout();
        final ttW = tp.width + 12;
        final ttH = tp.height + 8;
        var ttX = x + barW / 2 - ttW / 2;
        if (ttX < leftPad) ttX = leftPad;
        if (ttX + ttW > size.width - rightPad) ttX = size.width - rightPad - ttW;
        final ttY = barTop - ttH - 4;

        final ttRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(ttX, ttY, ttW, ttH),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          ttRect,
          Paint()..color = Colors.black87,
        );
        tp.paint(canvas, Offset(ttX + 6, ttY + 4));
      }
    }
  }

  String _formatAmount(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  TextPainter _buildTextPainter(String text, double fontSize, Color color,
      {bool bold = false}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          height: 1.3,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.progress != progress ||
      old.data != data ||
      old.hoveredIndex != hoveredIndex;
}
