import 'package:flutter/material.dart';

/// Penanda ikon Stats pada daftar IconData navbar (line / terpilih).
/// Dirender oleh [NavIcon] sebagai ChartNoAxesColumnIncreasing (gaya Lucide),
/// karena ikon itu tidak ada di MingCute/iconsx_plus yang dipakai proyek.
const IconData kStatsIcon = IconData(0xF8FF, fontFamily: 'VynoraStatsGlyph');
const IconData kStatsIconFilled = IconData(0xF8FE, fontFamily: 'VynoraStatsGlyph');

/// Pengganti `Icon(...)` untuk navbar: ikon biasa dirender normal, penanda
/// Stats digambar sebagai vektor.
class NavIcon extends StatelessWidget {
  const NavIcon(this.icon, {super.key, this.size = 24, this.color});
  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.white;
    if (icon == kStatsIcon || icon == kStatsIconFilled) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _StatsPainter(c, icon == kStatsIconFilled ? 2.6 : 2.0),
        ),
      );
    }
    return Icon(icon, size: size, color: color);
  }
}

/// Lucide "chart-no-axes-column-increasing" (viewBox 24x24):
/// garis x=6 y16-20, x=12 y10-20, x=18 y4-20, ujung bulat.
class _StatsPainter extends CustomPainter {
  _StatsPainter(this.color, this.stroke);
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 24;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke * k;
    void line(double x, double y1, double y2) =>
        canvas.drawLine(Offset(x * k, y1 * k), Offset(x * k, y2 * k), p);
    line(6, 20, 16);
    line(12, 20, 10);
    line(18, 20, 4);
  }

  @override
  bool shouldRepaint(_StatsPainter o) => o.color != color || o.stroke != stroke;
}
