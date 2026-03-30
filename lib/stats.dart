import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';

class StatsPage extends StatelessWidget {
  final int aura;
  final List tasks;
  final List<int> auraHistory;
  final List<DateTime?> auraDates;
  final List completedTasks;

  const StatsPage({
    super.key,
    required this.aura,
    required this.tasks,
    required this.auraHistory,
    required this.auraDates,
    required this.completedTasks,
  });

  String _auraStatus(int aura) {
    if (aura < 10) return "Huge L Aura";
    if (aura < 45) return "L Aura";
    if (aura < 100) return "Average Aura";
    if (aura < 150) return "Positive Aura";
    if (aura < 250) return "W Aura";
    if (aura < 500) return "Huge W Aura";
    return "Ascended Aura";
  }

  Color _auraColor(int aura, BuildContext context) {
    if (aura < 10) return Colors.red.shade900;
    if (aura < 45) return Colors.red;
    if (aura < 100) return Colors.orange;
    if (aura < 150) return Colors.yellow.shade700;
    if (aura < 250) return Colors.green;
    if (aura < 400) return Colors.blue;
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    int easy = completedTasks
        .where((t) => t.intensity == 'easy' && t.type == 'good')
        .length;
    int medium = completedTasks
        .where((t) => t.intensity == 'medium' && t.type == 'good')
        .length;
    int hard = completedTasks
        .where((t) => t.intensity == 'hard' && t.type == 'good')
        .length;
    int bad = completedTasks.where((t) => t.type == 'bad').length;

    final auraStatus = _auraStatus(aura);
    final auraColor = _auraColor(aura, context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Stats',
          style: GoogleFonts.gabarito(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ListView(
          children: [
            Text(
              'Aura Meter',
              style: GoogleFonts.gabarito(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _AuraMeter(aura: aura, status: auraStatus, color: auraColor),
            const SizedBox(height: 32),
            Text(
              'Aura changes in the past',
              style: GoogleFonts.gabarito(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _AuraLineChart(
                auraTimeline: auraHistory,
                auraDates: auraDates,
                color: auraColor,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Completed Tasks Breakdown',
              style: GoogleFonts.gabarito(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _statChip(context, 'Good (Easy)', easy, Colors.green),
                _statChip(context, 'Good (Medium)', medium, Colors.orange),
                _statChip(context, 'Good (Hard)', hard, Colors.red),
                _statChip(context, 'Bad', bad, Colors.purple),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Total Completed Tasks: ${completedTasks.length}',
              style: GoogleFonts.gabarito(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(BuildContext context, String label, int count, Color color) {
    return Chip(
      label: Text(
        '$label: $count',
        style: GoogleFonts.gabarito(color: Colors.white),
      ),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

class _AuraMeter extends StatelessWidget {
  final int aura;
  final String status;
  final Color color;

  const _AuraMeter({
    required this.aura,
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    double percent = (aura / 500).clamp(0.0, 1.0);

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: percent,
                strokeWidth: 14,
                backgroundColor: color.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$aura',
                  style: GoogleFonts.ebGaramond(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  status,
                  style: GoogleFonts.gabarito(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _AuraLineChart extends StatelessWidget {
  final List<int> auraTimeline;
  final List<DateTime?> auraDates;
  final Color color;

  const _AuraLineChart({
    required this.auraTimeline,
    required this.auraDates,
    required this.color,
  });

  String _formatDate(DateTime? date, bool isLast) {
    if (isLast) return "Now";
    if (date == null) return "";

    return "${_monthShort(date.month)} ${date.day}";
  }

  String _monthShort(int month) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (auraTimeline.isEmpty) {
      return Center(
        child: Text("No Aura history yet.", style: GoogleFonts.gabarito()),
      );
    }
    final maxAura = auraTimeline.reduce(max).toDouble();
    final minAura = auraTimeline.reduce(min).toDouble();
    final points = auraTimeline.length;

    return Stack(
      children: [
        CustomPaint(
          painter: _LineChartPainter(auraTimeline, color, minAura, maxAura),
          child: SizedBox(height: 180, width: double.infinity),
        ),
        Positioned(
          bottom: 0,
          left: 8,
          right: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              points,
              (i) => Text(
                _formatDate(
                  i < auraDates.length ? auraDates[i] : null,
                  i == points - 1,
                ),
                style: GoogleFonts.gabarito(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<int> data;
  final Color color;
  final double minAura;
  final double maxAura;

  _LineChartPainter(this.data, this.color, this.minAura, this.maxAura);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final int n = data.length;
    final double chartHeight = size.height - 32;
    final double chartWidth = size.width;

    final double yRange = (maxAura - minAura).abs() < 1e-6
        ? 1
        : (maxAura - minAura);
    final double dx = n > 1 ? chartWidth / (n - 1) : 0;

    Path path = Path();
    for (int i = 0; i < n; i++) {
      double x = n > 1 ? i * dx : chartWidth / 2;
      double y =
          chartHeight - ((data[i] - minAura) / yRange) * chartHeight + 16;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
    }
    if (n == 1) {
      double x = chartWidth / 2;
      double y =
          chartHeight - ((data[0] - minAura) / yRange) * chartHeight + 16;
      canvas.drawLine(Offset(x - 10, y), Offset(x + 10, y), paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) => true;
}
