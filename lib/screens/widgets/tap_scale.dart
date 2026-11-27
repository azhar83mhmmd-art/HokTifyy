import 'package:flutter/material.dart';

/// Efek tekan ringan untuk kartu: mengecil sedikit saat disentuh.
/// Memakai Listener sehingga tidak bentrok dengan GestureDetector/InkWell
/// di dalamnya maupun dengan scroll.
class TapScale extends StatefulWidget {
  const TapScale({super.key, required this.child, this.pressedScale = 0.96});

  final Widget child;
  final double pressedScale;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
