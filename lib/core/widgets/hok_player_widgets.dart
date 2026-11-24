import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:streambeats/core/theme/app_theme.dart';

/// Komponen UI pemutar bergaya "Sonara" dengan ciri khas Vynora Music:
///  * [WavySeekBar]      – progress bar bergelombang (gelombang suara).
///  * [SoundArcs]        – lengkung gelombang suara di sisi sampul (diambil
///                         dari logo Vynora Music), berdenyut saat lagu diputar.
///  * [HokSegmentedTabs] – tab segmented berbentuk pil.
///  * [HokPillChip]      – chip aksi kecil (EQ, Timer, Kecepatan, dst).

// ---------------------------------------------------------------------------
// WavySeekBar
// ---------------------------------------------------------------------------

class WavySeekBar extends StatefulWidget {
  const WavySeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onSeek,
    this.activeColor = Default_Theme.accentColor2,
    this.inactiveColor = const Color(0x2EFFFFFF),
    this.height = 40,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final ValueChanged<Duration> onSeek;
  final Color activeColor;
  final Color inactiveColor;
  final double height;

  @override
  State<WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<WavySeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Nilai 0..1 saat pengguna sedang menggeser; null jika tidak.
  double? _drag;

  @override
  void initState() {
    super.initState();
    _syncPhase();
  }

  @override
  void didUpdateWidget(covariant WavySeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _syncPhase();
  }

  void _syncPhase() {
    if (widget.isPlaying) {
      _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  double get _streamFraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }

  void _setDrag(double dx, double width) {
    if (width <= 0) return;
    setState(() => _drag = (dx / width).clamp(0.0, 1.0).toDouble());
  }

  void _commit(double fraction) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return;
    widget.onSeek(Duration(milliseconds: (fraction * total).round()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            HapticFeedback.selectionClick();
            _commit((d.localPosition.dx / width).clamp(0.0, 1.0).toDouble());
          },
          onHorizontalDragStart: (d) => _setDrag(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _setDrag(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) {
            final v = _drag;
            setState(() => _drag = null);
            if (v != null) _commit(v);
          },
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: widget.isPlaying ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, amplitude, _) {
                return AnimatedBuilder(
                  animation: _phase,
                  builder: (context, __) {
                    return CustomPaint(
                      painter: _WavyPainter(
                        fraction: _drag ?? _streamFraction,
                        phase: _phase.value * 2 * math.pi,
                        amplitude: amplitude,
                        dragging: _drag != null,
                        active: widget.activeColor,
                        inactive: widget.inactiveColor,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter({
    required this.fraction,
    required this.phase,
    required this.amplitude,
    required this.dragging,
    required this.active,
    required this.inactive,
  });

  final double fraction;
  final double phase;
  final double amplitude; // 0..1
  final bool dragging;
  final Color active;
  final Color inactive;

  static const double _stroke = 4.5;
  static const double _wavelength = 26;
  static const double _maxAmp = 4.2;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final xp = (size.width * fraction).clamp(0.0, size.width).toDouble();
    const pad = _stroke / 2;

    // Bagian belum diputar: garis lurus.
    if (xp < size.width - pad) {
      canvas.drawLine(
        Offset(math.max(xp, pad), cy),
        Offset(size.width - pad, cy),
        Paint()
          ..color = inactive
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Bagian sudah diputar: gelombang sinus bergeser.
    if (xp > pad) {
      final amp = _maxAmp * amplitude;
      final path = Path();
      for (double x = pad; x <= xp; x += 1.5) {
        // Gelombang mengecil di ujung kiri agar awalnya "tumbuh" halus.
        final fade = math.min(1.0, (x - pad) / 18);
        final y = cy + math.sin((x / _wavelength) * 2 * math.pi - phase) *
            amp *
            fade;
        if (x == pad) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = LinearGradient(
            colors: [Default_Theme.accentColor1, active],
          ).createShader(Rect.fromLTWH(0, 0, math.max(xp, 1), size.height)),
      );
    }

    // Thumb: pil vertikal.
    final thumbH = dragging ? 30.0 : 24.0;
    final thumbW = dragging ? 6.0 : 5.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(xp.clamp(thumbW, size.width - thumbW).toDouble(), cy),
          width: thumbW,
          height: thumbH),
      Radius.circular(thumbW),
    );
    canvas.drawRRect(
      r.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(r, Paint()..color = active);
  }

  @override
  bool shouldRepaint(covariant _WavyPainter old) =>
      old.fraction != fraction ||
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.dragging != dragging ||
      old.active != active ||
      old.inactive != inactive;
}

// ---------------------------------------------------------------------------
// SoundArcs  (ciri khas Vynora Music: lengkung gelombang suara dari logo)
// ---------------------------------------------------------------------------

class SoundArcs extends StatefulWidget {
  const SoundArcs({
    super.key,
    required this.isPlaying,
    required this.child,
    this.color = Default_Theme.accentColor2,
  });

  final bool isPlaying;
  final Widget child;
  final Color color;

  @override
  State<SoundArcs> createState() => _SoundArcsState();
}

class _SoundArcsState extends State<SoundArcs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SoundArcs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _sync();
  }

  void _sync() {
    if (widget.isPlaying) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        return CustomPaint(
          painter: _ArcsPainter(
            t: _c.value,
            playing: widget.isPlaying,
            color: widget.color,
          ),
          child: child,
        );
      },
    );
  }
}

class _ArcsPainter extends CustomPainter {
  _ArcsPainter({required this.t, required this.playing, required this.color});

  final double t;
  final bool playing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 9.0;
    const step = 10.0;
    const bulge = 6.0;
    final cy = size.height / 2;

    for (int i = 0; i < 2; i++) {
      final half = size.height * (0.14 + 0.08 * i);
      final alpha = playing
          ? 0.16 + 0.70 * ((math.sin((t - i * 0.18) * 2 * math.pi) + 1) / 2)
          : 0.20;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: alpha);

      final dx = gap + i * step;

      final left = Path()
        ..moveTo(-dx, cy - half)
        ..quadraticBezierTo(-dx - bulge * 2, cy, -dx, cy + half);
      final right = Path()
        ..moveTo(size.width + dx, cy - half)
        ..quadraticBezierTo(
            size.width + dx + bulge * 2, cy, size.width + dx, cy + half);

      canvas.drawPath(left, paint);
      canvas.drawPath(right, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcsPainter old) =>
      old.t != t || old.playing != playing || old.color != color;
}

// ---------------------------------------------------------------------------
// HokSegmentedTabs
// ---------------------------------------------------------------------------

class HokSegmentedTabs extends StatelessWidget {
  const HokSegmentedTabs({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onChanged,
  }) : assert(labels.length == icons.length);

  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: i == selectedIndex
                      ? Default_Theme.primaryContainerColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icons[i],
                      size: 14,
                      color: i == selectedIndex
                          ? Default_Theme.onPrimaryContainerColor
                          : Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      labels[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == selectedIndex
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == selectedIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HokPillChip
// ---------------------------------------------------------------------------

class HokPillChip extends StatelessWidget {
  const HokPillChip({
    super.key,
    required this.icon,
    this.label,
    this.onTap,
    this.highlighted = false,
    this.trailing,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final bool highlighted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = highlighted
        ? Default_Theme.onPrimaryContainerColor
        : Colors.white.withValues(alpha: 0.85);
    return Material(
      color: highlighted
          ? Default_Theme.primaryContainerColor
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: label == null ? 11 : 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 2),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
