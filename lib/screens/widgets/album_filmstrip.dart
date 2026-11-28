import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:streambeats/core/models/exported.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/utils/load_image.dart';
import 'package:streambeats/utils/pallete_generator.dart';

/// Album Filmstrip: cover album berjajar horizontal seperti frame film.
/// - Album terpilih di tengah, lebih besar & terang; lainnya mengecil & redup.
/// - Geser horizontal dengan snapping (PageScrollPhysics) per album.
/// - Latar menyesuaikan warna dominan artwork terpilih (transisi halus).
/// - Ketuk album terpilih -> detail (Hero shared-element); ketuk album di
///   samping -> pindah ke tengah.
class AlbumFilmstrip extends StatefulWidget {
  const AlbumFilmstrip({
    super.key,
    required this.albums,
    required this.onOpen,
    this.onNearEnd,
    this.isLoadingMore = false,
  });

  final List<AlbumSummary> albums;

  /// Dipanggil saat album terpilih diketuk. [heroTag] dipakai AlbumView agar
  /// artwork berpindah mulus (shared-element).
  final void Function(AlbumSummary album, String heroTag) onOpen;

  /// Dipanggil saat fokus mendekati akhir daftar (untuk memuat lebih banyak).
  final VoidCallback? onNearEnd;
  final bool isLoadingMore;

  @override
  State<AlbumFilmstrip> createState() => _AlbumFilmstripState();
}

class _AlbumFilmstripState extends State<AlbumFilmstrip> {
  static const double _fraction = 0.52;
  static const double _maxWidth = 600;

  // Cache warna dominan per URL (dibatasi agar memori terkendali).
  static final Map<String, Color> _colorCache = {};

  late final PageController _controller;
  final ValueNotifier<int> _focus = ValueNotifier<int>(0);
  late final String _tagPrefix;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: _fraction);
    _tagPrefix = 'filmstrip_${identityHashCode(this)}';
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureColor(0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _urlOf(int i) {
    if (i < 0 || i >= widget.albums.length) return null;
    final u = widget.albums[i].thumbnail?.url;
    return (u == null || u.isEmpty) ? null : u;
  }

  Future<void> _ensureColor(int i) async {
    final url = _urlOf(i);
    if (url == null || _colorCache.containsKey(url)) return;
    try {
      final palette = await getPalleteFromImage(url);
      final c = palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.mutedColor?.color;
      if (c == null) return;
      if (_colorCache.length > 64) _colorCache.remove(_colorCache.keys.first);
      _colorCache[url] = c;
      if (mounted && _focus.value == i) setState(() {});
    } catch (_) {}
  }

  void _onPageChanged(int i) {
    if (i == _focus.value) return;
    HapticFeedback.selectionClick();
    _focus.value = i;
    _ensureColor(i);
    if (widget.onNearEnd != null && i >= widget.albums.length - 3) {
      widget.onNearEnd!();
    }
  }

  void _onTap(int i) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (i == _focus.value) {
      widget.onOpen(widget.albums[i], '${_tagPrefix}_$i');
    } else if (reduce) {
      _controller.jumpToPage(i);
    } else {
      _controller.animateToPage(i,
          duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = widget.albums;
    if (albums.isEmpty) return const _FilmstripEmpty();

    final reduce = MediaQuery.disableAnimationsOf(context);
    final focus = _focus.value.clamp(0, albums.length - 1);
    final bg = _colorCache[_urlOf(focus)] ?? Default_Theme.accentColor1;
    final tint = Color.lerp(bg, Colors.black, 0.45)!;

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.clamp(0.0, _maxWidth);
      final pageW = w * _fraction;
      final stripH = pageW + 12;

      return Center(
        child: SizedBox(
          width: w,
          child: Stack(
            children: [
              // Latar adaptif warna artwork.
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: tint),
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (_, color, __) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (color ?? tint).withValues(alpha: 0.42),
                            (color ?? tint).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 14),
                  SizedBox(
                    height: stripH,
                    child: ScrollConfiguration(
                      // Geser dengan mouse/trackpad juga (desktop).
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: albums.length,
                        onPageChanged: _onPageChanged,
                        physics: const PageScrollPhysics(),
                        clipBehavior: Clip.none,
                        itemBuilder: (context, i) => _FilmFrame(
                          key: ValueKey('${albums[i].id}_$i'),
                          album: albums[i],
                          controller: _controller,
                          index: i,
                          reduceMotion: reduce,
                          heroTag: '${_tagPrefix}_$i',
                          onTap: () => _onTap(i),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Judul + artis album terpilih.
                  ValueListenableBuilder<int>(
                    valueListenable: _focus,
                    builder: (_, i, __) {
                      final a = albums[i.clamp(0, albums.length - 1)];
                      final artists = a.artists.map((e) => e.name).join(', ');
                      return AnimatedSwitcher(
                        duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                        child: Padding(
                          key: ValueKey(a.id),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              Text(
                                a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700),
                              ),
                              if (artists.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  artists,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 13),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: _focus,
                    builder: (_, i, __) => _PositionIndicator(
                        count: albums.length, index: i.clamp(0, albums.length - 1)),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Satu frame: skala + opasitas mengikuti jarak ke posisi fokus.
class _FilmFrame extends StatelessWidget {
  const _FilmFrame({
    super.key,
    required this.album,
    required this.controller,
    required this.index,
    required this.reduceMotion,
    required this.heroTag,
    required this.onTap,
  });

  final AlbumSummary album;
  final PageController controller;
  final int index;
  final bool reduceMotion;
  final String heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = Hero(
      tag: heroTag,
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: LoadImageCached(
              imageUrl: album.thumbnail?.url ?? '',
              fallbackUrl: album.thumbnail?.urlLow,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        // Gambar dibangun sekali; hanya transform yang dihitung ulang saat scroll.
        child: Semantics(
          button: true,
          label: 'Album ${album.title}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Center(child: art)),
          ),
        ),
        builder: (context, child) {
          double page;
          try {
            page = controller.page ?? controller.initialPage.toDouble();
          } catch (_) {
            page = controller.initialPage.toDouble();
          }
          final d = (page - index).abs().clamp(0.0, 1.0);
          final scale = reduceMotion ? 1.0 : 1.0 - 0.15 * d;
          final opacity = 1.0 - 0.55 * d;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          );
        },
      ),
    );
  }
}

/// Indikator posisi minimal: garis tipis dengan segmen yang bergeser.
class _PositionIndicator extends StatelessWidget {
  const _PositionIndicator({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: 3);
    const track = 72.0;
    final seg = (track / count).clamp(14.0, track);
    final left = (index / (count - 1)) * (track - seg);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Album ${index + 1} of $count',
      child: SizedBox(
        width: track,
        height: 3,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(2)),
          ),
          AnimatedPositioned(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            left: left,
            width: seg,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FilmstripEmpty extends StatelessWidget {
  const _FilmstripEmpty();

  @override
  Widget build(BuildContext context) => Container(
        height: 168,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Default_Theme.surfaceColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Default_Theme.outlineColor),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.album_outlined, size: 30, color: Colors.white.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text('No albums to show yet',
              style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
        ]),
      );
}
