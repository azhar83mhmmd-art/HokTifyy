import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:streambeats/core/theme/app_theme.dart';

/// Kaca cair (liquid glass) yang selaras dengan MorphBar: blur latar + tint
/// tipis + cahaya tepi bagian dalam + sorot lembut dari atas + garis tepi
/// halus. Dipakai secukupnya (radial menu, pemilih periode, sheet profil).
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.circle = false,
    this.blur = 22,
    this.tint,
    this.tintAlpha = 0.34,
    this.active = false,
    this.padding,
  });

  final Widget child;
  final double radius;

  /// true -> bentuk lingkaran sempurna.
  final bool circle;
  final double blur;
  final Color? tint;
  final double tintAlpha;

  /// Keadaan sorot (mis. opsi yang sedang disentuh): tint aksen lebih kuat.
  final bool active;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final base = tint ??
        Color.lerp(Default_Theme.surfaceColor, Default_Theme.themeColor, 0.35)!;
    final fill = active ? Default_Theme.primaryContainerColor : base;
    final inner = CustomPaint(
      painter: _GlassPainter(
        radius: radius,
        circle: circle,
        tint: fill,
        tintAlpha: active ? 0.82 : tintAlpha,
        edge: active ? Default_Theme.accentColor2 : Colors.white,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    final glass = BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: inner,
    );
    return RepaintBoundary(
      child: circle
          ? ClipOval(child: glass)
          : ClipRRect(borderRadius: BorderRadius.circular(radius), child: glass),
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({
    required this.radius,
    required this.circle,
    required this.tint,
    required this.tintAlpha,
    required this.edge,
  });

  final double radius;
  final bool circle;
  final Color tint;
  final double tintAlpha;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = circle ? size.shortestSide / 2 : radius;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    canvas.drawRRect(rrect, Paint()..color = tint.withValues(alpha: tintAlpha));
    canvas.drawRRect(
        rrect, Paint()..color = Colors.white.withValues(alpha: 0.07));

    canvas.save();
    canvas.clipRRect(rrect);

    // Cahaya tepi dalam (kesan ketebalan kaca).
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = edge.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Sorot lembut dari atas + redaman di dasar.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.05),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    canvas.restore();

    // Garis tepi halus.
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter o) =>
      o.radius != radius ||
      o.circle != circle ||
      o.tint != tint ||
      o.tintAlpha != tintAlpha ||
      o.edge != edge;
}
