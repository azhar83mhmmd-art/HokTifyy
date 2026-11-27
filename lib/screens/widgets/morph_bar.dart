import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/blocs/mini_player/mini_player_cubit.dart';
import 'package:streambeats/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:streambeats/core/models/exported.dart' hide MediaItem;
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/l10n/app_localizations.dart';
import 'package:streambeats/screens/widgets/artwork_anchors.dart';
import 'package:streambeats/utils/load_image.dart';

/// MorphBar - SATU komponen navigasi dengan dua keadaan:
///
///  * Expanded  : island pemutar (di atas) + navbar 5 tab (di bawah).
///  * Collapsed : satu pill kaca berisi ikon Home + island pemutar ringkas.
///
/// Perpindahan keadaan digerakkan satu nilai `t` (0 = expanded, 1 = collapsed)
/// oleh simulasi pegas (underdamped) sehingga bentuk "cair" sedikit melewati
/// target lalu mengendap. Seluruh permukaan kaca digambar sebagai SATU path
/// gabungan (union) dengan SATU BackdropFilter, jadi blur tetap murah dan
/// dua pill benar-benar menyatu menjadi satu bentuk.
class MorphBar extends StatefulWidget {
  const MorphBar({
    super.key,
    required this.navigationShell,
    required this.collapsed,
  });

  final StatefulNavigationShell navigationShell;

  /// Diisi oleh pendengar scroll di GlobalFooter.
  final ValueNotifier<bool> collapsed;

  @override
  State<MorphBar> createState() => _MorphBarState();
}

class _MorphBarState extends State<MorphBar> with TickerProviderStateMixin {
  late final AnimationController _t; // 0 expanded .. 1 collapsed (boleh overshoot)
  late final AnimationController _presence; // island muncul / hilang
  MiniPlayerState? _lastVisible;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 21,
  );

  @override
  void initState() {
    super.initState();
    _t = AnimationController.unbounded(
      vsync: this,
      value: widget.collapsed.value ? 1 : 0,
    );
    final visible = context.read<MiniPlayerCubit>().state;
    _presence = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: visible.isVisible ? 1 : 0,
    );
    if (visible.isVisible) _lastVisible = visible;
    widget.collapsed.addListener(_onCollapsedChanged);
  }

  @override
  void didUpdateWidget(covariant MorphBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed) {
      oldWidget.collapsed.removeListener(_onCollapsedChanged);
      widget.collapsed.addListener(_onCollapsedChanged);
    }
  }

  @override
  void dispose() {
    widget.collapsed.removeListener(_onCollapsedChanged);
    _t.dispose();
    _presence.dispose();
    super.dispose();
  }

  void _onCollapsedChanged() {
    final target = widget.collapsed.value ? 1.0 : 0.0;
    _t.animateWith(SpringSimulation(_spring, _t.value, target, _t.velocity));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MiniPlayerCubit, MiniPlayerState>(
      listenWhen: (a, b) => a.isVisible != b.isVisible,
      listener: (_, s) {
        if (s.isVisible) {
          _presence.forward();
        } else {
          _presence.reverse();
        }
      },
      builder: (context, state) {
        if (state.isVisible) _lastVisible = state;
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, c) => RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_t, _presence]),
                  builder: (context, _) =>
                      _buildBar(context, c.maxWidth, state),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBar(BuildContext context, double barW, MiniPlayerState state) {
    final l10n = AppLocalizations.of(context)!;
    final t = _t.value; // dapat overshoot untuk efek elastis
    final tc = t.clamp(0.0, 1.0).toDouble();
    final p = Curves.easeOutCubic.transform(_presence.value);
    final geo = _Geo(barW: barW, t: t, p: p);
    final shell = widget.navigationShell;

    // Squash & stretch tipis mengikuti kecepatan pegas.
    final stretch = (_t.velocity.abs() * 0.010).clamp(0.0, 0.045).toDouble();

    final path = geo.glassPath();
    final tint = Color.lerp(
        Default_Theme.surfaceColor, Default_Theme.themeColor, 0.35)!;

    final items = <(IconData, IconData, String)>[
      (MingCute.home_4_line, MingCute.home_4_fill, l10n.navHome),
      (MingCute.book_5_line, MingCute.book_5_fill, l10n.navLibrary),
      (MingCute.search_2_line, MingCute.search_2_fill, l10n.navSearch),
      (MingCute.music_2_line, MingCute.music_2_fill, l10n.navLocal),
      (MingCute.folder_download_line, MingCute.folder_download_fill,
          l10n.navOffline),
    ];

    final nav = geo.nav;
    final islandState = state.isVisible ? state : _lastVisible;

    return SizedBox(
      // Tinggi yang dilaporkan ke Scaffold ikut presence agar tidak ada
      // ruang kosong saat belum ada lagu. Isi tetap digambar di koordinat
      // tinggi penuh (bottom-anchored).
      height: _Geo.navH + p * (_Geo.islandH + _Geo.gap),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _Geo.fullH,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(
                  1 + stretch, 1 - stretch * 0.8, 1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Bayangan lembut (tidak ikut ter-clip).
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _ShadowPainter(path)),
                    ),
                  ),
                  // Permukaan kaca: satu clip + satu blur untuk seluruh bentuk.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipPath(
                        clipper: _PathClipper(path),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                          child: CustomPaint(
                            painter:
                                _GlassPainter(path: path, t: tc, tint: tint),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Island pemutar (compact saat collapsed, expanded saat tidak).
                  if (islandState != null && p > 0.02)
                    Positioned.fromRect(
                      rect: geo.islandLayoutRect,
                      child: Opacity(
                        opacity: p.clamp(0.0, 1.0).toDouble(),
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * p,
                          alignment: Alignment.bottomCenter,
                          child: _Island(state: islandState, collapse: tc),
                        ),
                      ),
                    ),

                  // Ikon navigasi: selain Home tersedot lalu memudar.
                  for (var i = 0; i < items.length; i++)
                    _buildNavItem(
                      geo: geo,
                      index: i,
                      tc: tc,
                      selected: shell.currentIndex == i,
                      icon: items[i].$1,
                      activeIcon: items[i].$2,
                      label: items[i].$3,
                      navRect: nav,
                      barW: barW,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required _Geo geo,
    required int index,
    required double tc,
    required bool selected,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required Rect navRect,
    required double barW,
  }) {
    final isHome = index == 0;
    final expCx = barW * (index + 0.5) / 5;
    final pull = Curves.easeInOutCubic.transform(tc);
    final cx = navRect.center.dx + (expCx - barW / 2) * (1 - pull);

    final fade = isHome ? 1.0 : 1.0 - _smooth(0.0, 0.55, tc);
    final scale = isHome ? 1.0 : ui.lerpDouble(1.0, 0.5, _smooth(0, 0.6, tc))!;
    final collapsedEnough = tc > 0.5;

    return Positioned(
      left: cx - 36,
      top: navRect.top,
      width: 72,
      height: navRect.height,
      child: IgnorePointer(
        ignoring: !isHome && collapsedEnough,
        child: Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: scale,
            child: _Pressable(
              onTap: () {
                HapticFeedback.selectionClick();
                if (isHome && widget.collapsed.value) {
                  widget.collapsed.value = false;
                }
                widget.navigationShell.goBranch(
                  index,
                  initialLocation: index == widget.navigationShell.currentIndex,
                );
              },
              child: _NavGlyph(
                selected: selected,
                icon: selected ? activeIcon : icon,
                label: label,
                collapse: isHome ? tc : 0.0,
                labelFade: 1.0 - _smooth(0.0, 0.25, tc),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _smooth(double a, double b, double x) {
  final v = ((x - a) / (b - a)).clamp(0.0, 1.0).toDouble();
  return v * v * (3 - 2 * v);
}

// ---------------------------------------------------------------------------
// Geometri: semua persegi panjang untuk nilai t (collapse) dan p (presence).
// Koordinat: asal di kiri-atas area setinggi [fullH]; bar menempel di bawah.
// ---------------------------------------------------------------------------
class _Geo {
  _Geo({required this.barW, required this.t, required this.p});

  static const double navH = 64;
  static const double islandH = 64;
  static const double gap = 8;
  static const double fullH = navH + gap + islandH;
  static const double colH = 56;
  static const double homeW = 56;
  static const double radius = 28;

  final double barW;
  final double t;
  final double p;

  double get _islandColW => math.min(barW - homeW, 252);
  double get _collW => homeW + _islandColW * p;
  double get _collLeft => (barW - _collW) / 2;

  Rect get _navExp => Rect.fromLTWH(0, fullH - navH, barW, navH);
  Rect get _navCol =>
      Rect.fromLTWH(_collLeft, fullH - colH, homeW, colH);
  Rect get _islandExp => Rect.fromLTWH(0, 0, barW, islandH);
  Rect get _islandCol =>
      Rect.fromLTWH(_collLeft + homeW, fullH - colH, _islandColW, colH);
  Rect get _mergedCol =>
      Rect.fromLTWH(_collLeft, fullH - colH, _collW, colH);

  Rect get nav => Rect.lerp(_navExp, _navCol, t)!;

  /// Persegi island untuk tata letak isi (belum diskalakan oleh presence).
  Rect get islandLayoutRect => Rect.lerp(_islandExp, _islandCol, t)!;

  /// Persegi island untuk bentuk kaca (tumbuh dari titik di atas navbar).
  Rect get _island {
    final r = islandLayoutRect;
    final w = r.width * p;
    final h = r.height * p;
    return Rect.fromLTWH(r.center.dx - w / 2, r.bottom - h, w, h);
  }

  /// Pill penghubung: navbar yang "menelan" island saat collapse.
  Rect get _merged =>
      Rect.lerp(_navExp, _mergedCol, Curves.easeInOut.transform(
          t.clamp(0.0, 1.0).toDouble()))!;

  RRect _rr(Rect r) {
    final rad = math.min(radius, math.min(r.width, r.height) / 2);
    return RRect.fromRectAndRadius(r, Radius.circular(math.max(0, rad)));
  }

  Path glassPath() {
    var path = Path()..addRRect(_rr(nav));
    path = Path.combine(
        PathOperation.union, path, Path()..addRRect(_rr(_merged)));
    if (p > 0.05) {
      path = Path.combine(
          PathOperation.union, path, Path()..addRRect(_rr(_island)));
    }
    return path;
  }
}

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => true;
}

class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.path);
  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(covariant _ShadowPainter oldDelegate) => true;
}

/// Permukaan kaca cair: isian tembus pandang, cahaya atas, kilap diagonal yang
/// bergeser mengikuti morph, dan bingkai tipis bergradasi (terang di kiri-atas).
class _GlassPainter extends CustomPainter {
  _GlassPainter({required this.path, required this.t, required this.tint});

  final Path path;
  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;

    canvas.drawPath(path, Paint()..color = tint.withValues(alpha: 0.50));

    canvas.save();
    canvas.clipPath(path);

    // Cahaya lembut dari atas (bukan putih pekat) + redaman di dasar.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.10),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(bounds),
    );

    // Kilap diagonal yang bergeser saat bentuk berubah.
    final cx = ui.lerpDouble(
        bounds.left - 40, bounds.right + 40, (0.18 + 0.64 * t).clamp(0.0, 1.0))!;
    final streak = Path()
      ..moveTo(cx - 26, bounds.bottom)
      ..lineTo(cx + 6, bounds.bottom)
      ..lineTo(cx + 46, bounds.top)
      ..lineTo(cx + 14, bounds.top)
      ..close();
    canvas.drawPath(
      streak,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(cx - 20, bounds.top, 60, bounds.height)),
    );
    canvas.restore();

    // Bingkai tipis dengan highlight lembut.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.12),
          ],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Ikon navigasi
// ---------------------------------------------------------------------------
class _NavGlyph extends StatelessWidget {
  const _NavGlyph({
    required this.selected,
    required this.icon,
    required this.label,
    required this.collapse,
    required this.labelFade,
  });

  final bool selected;
  final IconData icon;
  final String label;

  /// 0..1, hanya untuk Home: indikator berubah menjadi lingkaran saat collapse.
  final double collapse;
  final double labelFade;

  @override
  Widget build(BuildContext context) {
    final w = ui.lerpDouble(60, 44, collapse)!;
    final h = ui.lerpDouble(32, 44, collapse)!;
    final dy = ui.lerpDouble(-9, 0, _smooth(0, 0.6, collapse))!;

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: Offset(0, dy),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: selected ? 1 : 0,
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: Default_Theme.accentColor2.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(h / 2),
                  ),
                ),
              ),
              Icon(
                icon,
                size: 22,
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.60),
              ),
            ],
          ),
        ),
        if (labelFade > 0.01)
          Transform.translate(
            offset: const Offset(0, 18),
            child: Opacity(
              opacity: labelFade,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Efek tekan: mengecil halus saat disentuh.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Island pemutar
// ---------------------------------------------------------------------------
class _Island extends StatefulWidget {
  const _Island({required this.state, required this.collapse});
  final MiniPlayerState state;

  /// 0 = expanded island, 1 = compact island.
  final double collapse;

  @override
  State<_Island> createState() => _IslandState();
}

class _IslandState extends State<_Island> with SingleTickerProviderStateMixin {
  late final AnimationController _snap;
  double _dx = 0;

  static const double _swipeThreshold = 80;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _dx = _snap.value);
      });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _settle(double velocity) {
    _snap.value = _dx;
    _snap.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 380, damping: 26),
      _dx,
      0,
      velocity,
    ));
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    if (_dx < -_swipeThreshold || v < -600) {
      HapticFeedback.mediumImpact();
      player.skipToNext();
    } else if (_dx > _swipeThreshold || v > 600) {
      HapticFeedback.mediumImpact();
      player.skipToPrevious();
    }
    _settle(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final track = s.track!;
    final c = widget.collapse;
    final extra = _smooth(0.0, 0.5, c); // 0 expanded -> 1 hilang
    final thumb = track.thumbnail.urlLow ?? track.thumbnail.url;
    final artists = track.artists.map((a) => a.name).join(', ');
    final discSize = ui.lerpDouble(46, 40, c)!;
    final fb = (1 - (_dx.abs() / 320)).clamp(0.65, 1.0).toDouble();

    return Transform.translate(
      offset: Offset(_dx, 0),
      child: Opacity(
        opacity: fb,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            context.read<PlayerOverlayCubit>().showPlayer();
          },
          onHorizontalDragStart: (_) => _snap.stop(),
          onHorizontalDragUpdate: (d) =>
              setState(() => _dx += d.delta.dx * 0.85),
          onHorizontalDragEnd: _onDragEnd,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) {
              HapticFeedback.lightImpact();
              context.read<PlayerOverlayCubit>().showPlayer();
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_Geo.radius),
            child: Stack(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 10),
                    _RotatingDisc(
                      size: discSize,
                      imageUrl: thumb,
                      fallbackUrl: track.thumbnail.url,
                      trackKey: track.id,
                      isPlaying: s.isPlaying,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.08, 0),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(track.id),
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              artists,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _extraButton(
                      extra,
                      MingCute.skip_previous_fill,
                      () => context
                          .read<StreamBeatsPlayerCubit>()
                          .streambeatsPlayer
                          .skipToPrevious(),
                    ),
                    _PlayPauseButton(state: s),
                    _extraButton(
                      extra,
                      MingCute.skip_forward_fill,
                      () => context
                          .read<StreamBeatsPlayerCubit>()
                          .streambeatsPlayer
                          .skipToNext(),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
                const Positioned(
                  left: 22,
                  right: 22,
                  bottom: 5,
                  height: 2.5,
                  child: _IslandProgress(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tombol prev/next: hanya pada island expanded; menyusut hingga lebar 0.
  Widget _extraButton(double extra, IconData icon, VoidCallback onTap) {
    final f = (1 - extra).clamp(0.0, 1.0).toDouble();
    return ClipRect(
      child: Align(
        alignment: Alignment.centerRight,
        widthFactor: f,
        child: Opacity(
          opacity: f,
          child: IgnorePointer(
            ignoring: f < 0.5,
            child: _Pressable(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(icon,
                    size: 20, color: Colors.white.withValues(alpha: 0.85)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sampul berbentuk piringan hitam yang berputar pelan saat lagu diputar,
/// berhenti saat pause, dan melanjutkan dari sudut terakhir saat play lagi.
class _RotatingDisc extends StatefulWidget {
  const _RotatingDisc({
    required this.size,
    required this.imageUrl,
    required this.fallbackUrl,
    required this.trackKey,
    required this.isPlaying,
  });

  final double size;
  final String imageUrl;
  final String fallbackUrl;
  final String trackKey;
  final bool isPlaying;

  @override
  State<_RotatingDisc> createState() => _RotatingDiscState();
}

class _RotatingDiscState extends State<_RotatingDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rot;

  @override
  void initState() {
    super.initState();
    _rot = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (widget.isPlaying) _rot.repeat();
  }

  @override
  void didUpdateWidget(covariant _RotatingDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _rot.repeat(); // melanjutkan dari nilai terakhir
      } else {
        _rot.stop(); // berhenti di sudut saat ini
      }
    }
  }

  @override
  void dispose() {
    _rot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return ValueListenableBuilder<double>(
      valueListenable: ArtworkAnchors.discOpacity,
      builder: (context, o, child) => Opacity(opacity: o, child: child),
      child: SizedBox.square(
      key: ArtworkAnchors.disc,
      dimension: size,
      child: RepaintBoundary(
        child: RotationTransition(
          turns: _rot,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
                child: child,
              ),
            ),
            child: _DiscFace(
              key: ValueKey(widget.trackKey),
              size: size,
              imageUrl: widget.imageUrl,
              fallbackUrl: widget.fallbackUrl,
            ),
          ),
        ),
      ),
    ));
  }
}

class _DiscFace extends StatelessWidget {
  const _DiscFace({
    super.key,
    required this.size,
    required this.imageUrl,
    required this.fallbackUrl,
  });

  final double size;
  final String imageUrl;
  final String fallbackUrl;

  @override
  Widget build(BuildContext context) {
    final hole = size * 0.20;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: LoadImageCached(
              imageUrl: imageUrl,
              fallbackUrl: fallbackUrl,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(
          width: hole,
          height: hole,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Default_Theme.themeColor,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.22), width: 1),
          ),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({required this.state});
  final MiniPlayerState state;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _icon;

  @override
  void initState() {
    super.initState();
    _icon = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: widget.state.isPlaying ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isPlaying != widget.state.isPlaying) {
      widget.state.isPlaying ? _icon.forward() : _icon.reverse();
    }
  }

  @override
  void dispose() {
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;

    Widget inner;
    VoidCallback? onTap;

    if (s.isLoading || s.isResolving) {
      inner = const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
    } else if (s.isCompleted) {
      inner = const Icon(FontAwesome.rotate_right_solid,
          size: 18, color: Colors.white);
      onTap = () {
        HapticFeedback.mediumImpact();
        player.rewind();
      };
    } else {
      inner = AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _icon,
        size: 24,
        color: Colors.white,
      );
      onTap = () {
        HapticFeedback.lightImpact();
        s.isPlaying ? player.pause() : player.play();
      };
    }

    final button = Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.14), width: 0.5),
      ),
      child: Center(child: inner),
    );

    return onTap == null
        ? button
        : _Pressable(onTap: onTap, child: button);
  }
}

class _IslandProgress extends StatefulWidget {
  const _IslandProgress();

  @override
  State<_IslandProgress> createState() => _IslandProgressState();
}

class _IslandProgressState extends State<_IslandProgress> {
  late final Stream<ProgressBarStreams> _stream =
      context.read<StreamBeatsPlayerCubit>().progressStreams;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProgressBarStreams>(
      stream: _stream,
      builder: (context, snapshot) {
        double f = 0;
        final d = snapshot.data;
        if (d != null && d.duration != Duration.zero) {
          f = (d.position.inMilliseconds / d.duration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
              ),
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: f),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  builder: (context, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v,
                    child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
