import 'package:streambeats/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:streambeats/screens/screen/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/screens/widgets/artwork_anchors.dart';
import 'package:streambeats/utils/load_image.dart';

class PlayerOverlayWrapper extends StatefulWidget {
  final Widget child;

  const PlayerOverlayWrapper({
    super.key,
    required this.child,
  });

  @override
  State<PlayerOverlayWrapper> createState() => _PlayerOverlayWrapperState();
}

class _PlayerOverlayWrapperState extends State<PlayerOverlayWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _hasBeenShown = false;

  /// Artwork yang "terbang" antara piringan island dan sampul Now Playing.
  final ValueNotifier<_Flight?> _flight = ValueNotifier<_Flight?>(null);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.addListener(_tickFlight);
  }

  @override
  void dispose() {
    _animationController.removeListener(_tickFlight);
    _animationController.dispose();
    _flight.dispose();
    ArtworkAnchors.reset();
    super.dispose();
  }

  void _endFlight() {
    if (_flight.value != null) _flight.value = null;
    ArtworkAnchors.reset();
  }

  /// Menghitung posisi artwork di setiap frame animasi buka/tutup player.
  /// Jika salah satu jangkar belum tersedia, animasi slide biasa tetap jalan.
  void _tickFlight() {
    final v = _animationController.value;
    if (v <= 0.0 || v >= 1.0) {
      _endFlight();
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      _endFlight();
      return;
    }
    final begin = ArtworkAnchors.rectIn(ArtworkAnchors.disc, box);
    final endRaw = ArtworkAnchors.rectIn(ArtworkAnchors.cover, box);
    if (begin == null || endRaw == null) {
      _endFlight();
      return;
    }

    // Sampul asli ikut bergeser bersama slide; koreksi ke posisi akhirnya.
    final slideDy = _slideAnimation.value.dy * box.size.height;
    final end = endRaw.shift(Offset(0, -slideDy));
    final g = (1.0 - _slideAnimation.value.dy).clamp(0.0, 1.0).toDouble();

    final reveal = ((g - 0.88) / 0.12).clamp(0.0, 1.0).toDouble();
    ArtworkAnchors.coverOpacity.value = reveal;
    ArtworkAnchors.discOpacity.value = g > 0.02 ? 0.0 : 1.0;

    String? url;
    try {
      final t = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer
          .currentTrackInfo;
      url = t.thumbnail.urlHigh ?? t.thumbnail.url;
    } catch (_) {}
    if (url == null) {
      _endFlight();
      return;
    }

    _flight.value = _Flight(
      rect: Rect.lerp(begin, end, g)!,
      radius: (begin.shortestSide / 2) * (1 - g) + 28 * g,
      opacity: 1.0 - reveal,
      url: url,
    );
  }

  void _onPlayerVisibilityChanged(bool isVisible) {
    if (isVisible) {
      _hasBeenShown = true;
      FocusManager.instance.primaryFocus?.unfocus();
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PlayerOverlayCubit, bool>(
      listener: (context, isVisible) {
        _onPlayerVisibilityChanged(isVisible);
      },
      child: Stack(
        children: [
          widget.child,

          BlocBuilder<PlayerOverlayCubit, bool>(
            buildWhen: (previous, current) {
              return !_hasBeenShown && current;
            },
            builder: (context, isVisible) {
              if (!_hasBeenShown && !isVisible) {
                return const SizedBox.shrink();
              }

              if (isVisible && !_hasBeenShown) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _hasBeenShown = true;
                    });
                  }
                });
              }

              return AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Visibility(
                    visible: _animationController.value > 0,
                    maintainState: true, // Keep state when hidden
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: child,
                      ),
                    ),
                  );
                },
                child: const _PersistentPlayerView(),
              );
            },
          ),
          ValueListenableBuilder<_Flight?>(
            valueListenable: _flight,
            builder: (context, f, _) {
              if (f == null) return const SizedBox.shrink();
              return Positioned.fromRect(
                rect: f.rect,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: f.opacity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(f.radius),
                      child: LoadImageCached(
                        imageUrl: f.url,
                        fallbackUrl: f.url,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PersistentPlayerView extends StatelessWidget {
  const _PersistentPlayerView();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.transparent,
      child: AudioPlayerView(),
    );
  }
}

class _Flight {
  final Rect rect;
  final double radius;
  final double opacity;
  final String url;
  const _Flight({
    required this.rect,
    required this.radius,
    required this.opacity,
    required this.url,
  });
}
