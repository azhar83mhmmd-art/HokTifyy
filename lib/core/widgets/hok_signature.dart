import 'package:flutter/material.dart';

import 'package:streambeats/core/theme/app_theme.dart';

/// Motif khas HokTifyy: lengkung ganda (diambil dari logo) dalam gradien violet.
class ArchGlyph extends StatelessWidget {
  const ArchGlyph({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _ArchPainter());
}

class _ArchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8B5CF6), Color(0xFFCFBCFF)],
    ).createShader(Offset.zero & size);

    Paint stroke(double width, double alpha) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = shader
      ..color = Colors.white.withValues(alpha: alpha);

    Path arch(double inset) {
      final l = w * inset, r = w * (1 - inset);
      final rad = (r - l) / 2;
      return Path()
        ..moveTo(l, w * 0.92)
        ..lineTo(l, w * 0.92 - (w * 0.92 - rad - w * 0.06) * 0.55)
        ..arcToPoint(Offset(r, w * 0.92 - (w * 0.92 - rad - w * 0.06) * 0.55),
            radius: Radius.circular(rad))
        ..lineTo(r, w * 0.92);
    }

    canvas.drawPath(arch(0.04), stroke(w * 0.11, 0.45));
    canvas.drawPath(arch(0.27), stroke(w * 0.14, 1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Judul bagian gaya editorial: teks tebal besar + panah ke "lihat semua".
class HokSectionHeader extends StatelessWidget {
  const HokSectionHeader({super.key, required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSeeAll,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
        child: Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),
            if (onSeeAll != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 26, color: Colors.white.withValues(alpha: 0.55)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tiga batang ekualiser beranimasi — penanda lagu yang sedang diputar.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({super.key, this.size = 18, this.color});
  final double size;
  final Color? color;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Default_Theme.accentColor2;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          double h(double phase) {
            final t = (_c.value + phase) % 1.0;
            final v = t < 0.5 ? t * 2 : (1 - t) * 2;
            return 0.3 + 0.7 * v;
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in const [0.0, 0.33, 0.66])
                Container(
                  width: widget.size * 0.2,
                  height: widget.size * h(p),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
