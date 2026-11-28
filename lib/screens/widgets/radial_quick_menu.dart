import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:streambeats/blocs/add_to_playlist/cubit/add_to_playlist_cubit.dart';
import 'package:streambeats/blocs/library/cubit/library_items_cubit.dart';
import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/core/constants/route_paths.dart';
import 'package:streambeats/core/events/global_event_bus.dart';
import 'package:streambeats/core/models/exported.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:streambeats/plugins/utils/media_id.dart';
import 'package:streambeats/screens/screen/common_views/album_view.dart';
import 'package:streambeats/screens/screen/common_views/artist_view.dart';
import 'package:streambeats/screens/widgets/liquid_glass.dart';
import 'package:streambeats/screens/widgets/snackbar.dart';
import 'package:streambeats/utils/load_image.dart';

/// Bungkus artwork lagu: tekan & tahan -> Radial Quick Menu.
///
/// Gesture: tahan -> menu mengembang (spring) -> geser jari ke sebuah opsi ->
/// lepas = jalankan aksi. Lepas di luar opsi = menu tetap terbuka (mode ketuk):
/// ketuk opsi untuk menjalankan, ketuk area luar untuk menutup. Gesture yang
/// dibatalkan sistem menutup menu tanpa aksi. Long-press di luar artwork tetap
/// membuka sheet "more" yang sudah ada.
class RadialMenuArtwork extends StatefulWidget {
  const RadialMenuArtwork({super.key, required this.track, required this.child, this.enabled = true});

  final Track track;
  final Widget child;
  final bool enabled;

  @override
  State<RadialMenuArtwork> createState() => _RadialMenuArtworkState();
}

class _RadialMenuArtworkState extends State<RadialMenuArtwork> {
  _RadialSession? _session;

  @override
  void dispose() {
    _session?.dispose(runAction: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (d) {
        if (_session != null || _RadialSession.active) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final anchor = box.localToGlobal(box.size.center(Offset.zero));
        HapticFeedback.mediumImpact();
        _session = _RadialSession.open(context, widget.track, anchor, d.globalPosition);
      },
      onLongPressMoveUpdate: (d) => _session?.hover(d.globalPosition),
      onLongPressEnd: (d) {
        final s = _session;
        if (s == null) return;
        // Lepas di atas opsi -> jalankan; selain itu -> mode ketuk.
        if (!s.release(d.globalPosition)) return;
        _session = null;
      },
      onLongPressCancel: () {
        _session?.dispose(runAction: false);
        _session = null;
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------
// Sesi menu (overlay + state)
// ---------------------------------------------------------------------
class _Opt {
  const _Opt(this.id, this.label, this.icon, this.run, {this.enabled = true});
  final String id;
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback run;
}

class _RadialSession {
  _RadialSession._(this._entry, this.hoverIndex, this.opts, this.finger);

  static bool active = false;

  final OverlayEntry _entry;
  final ValueNotifier<int> hoverIndex;
  final ValueNotifier<List<_Opt>> opts;
  final ValueNotifier<Offset> finger;
  final ValueNotifier<bool> tapMode = ValueNotifier<bool>(false);
  late _Geometry geo;
  bool _closed = false;

  static _RadialSession open(
      BuildContext context, Track track, Offset anchor, Offset finger0) {
    // Semua dependensi diambil dari context sumber SEKARANG; overlay root
    // tidak bergantung pada context lain saat aksi dijalankan.
    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    final library = context.read<LibraryItemsCubit>();
    final playlistCubit = context.read<AddToPlaylistCubit>();
    final pluginBloc = context.read<PluginBloc>();
    final nav = Navigator.of(context);
    final router = GoRouter.of(context);

    final liked = ValueNotifier<bool>(false);

    List<_Opt> build(bool isLiked) {
      final album = track.album;
      final artist = track.artists.isEmpty ? null : track.artists.first;
      return [
        _Opt('like', isLiked ? 'Unlike' : 'Like',
            isLiked ? Icons.favorite_rounded : MingCute.heart_line, () async {
          await library.setTrackLiked(track, !isLiked);
          SnackbarService.showMessage(
              isLiked ? 'Removed from liked songs' : 'Added to liked songs');
        }),
        _Opt('playlist', 'Playlist', MingCute.add_circle_line, () {
          playlistCubit.setTrack(track);
          router.pushNamed(RoutePaths.addToPlaylistScreen);
        }),
        _Opt('queue', 'Queue', MingCute.playlist_2_line, () {
          player.addQueueTracks([track]);
          SnackbarService.showMessage('Added to queue');
        }),
        _Opt('share', 'Share', MingCute.share_forward_line, () {
          final url = track.url;
          if (url == null || url.isEmpty) {
            SnackbarService.showMessage('Nothing to share for this song');
            return;
          }
          SharePlus.instance.share(ShareParams(text: url, subject: track.title));
        }, enabled: true),
        _Opt('album', 'Album', MingCute.album_line, () {
          final pluginId = pluginIdOf(album!.id);
          if (pluginId == null ||
              !requirePlugin(pluginId, pluginBloc.state.loadedPluginIds)) {
            return;
          }
          nav.push(MaterialPageRoute(
              builder: (_) => AlbumView(album: album, pluginId: pluginId)));
        }, enabled: album != null),
        _Opt('artist', 'Artist', MingCute.user_3_fill, () {
          final pluginId = pluginIdOf(artist!.id);
          if (pluginId == null ||
              !requirePlugin(pluginId, pluginBloc.state.loadedPluginIds)) {
            return;
          }
          nav.push(MaterialPageRoute(
              builder: (_) => ArtistView(artist: artist, pluginId: pluginId)));
        }, enabled: artist != null),
      ];
    }

    final opts = ValueNotifier<List<_Opt>>(build(false));
    final hover = ValueNotifier<int>(-1);
    final fingerN = ValueNotifier<Offset>(finger0);

    late final _RadialSession session;
    final entry = OverlayEntry(
      builder: (_) => _RadialOverlay(
        track: track,
        anchor: anchor,
        media: media,
        opts: opts,
        hover: hover,
        finger: fingerN,
        tapMode: session.tapMode,
        onGeometry: (g) => session.geo = g,
        onSelect: (i) => session._select(i),
        onDismiss: () => session.dispose(runAction: false),
      ),
    );
    session = _RadialSession._(entry, hover, opts, fingerN);
    active = true;
    overlay.insert(entry);

    // Status like sebenarnya (async, tidak memblokir tampilan menu).
    library.isTrackLiked(track).then((v) {
      if (session._closed) return;
      liked.value = v;
      opts.value = build(v);
    }).catchError((_) {});

    return session;
  }

  void hover(Offset p) {
    finger.value = p;
    final i = _hit(p);
    if (i != hoverIndex.value) {
      hoverIndex.value = i;
      if (i >= 0) HapticFeedback.selectionClick();
    }
  }

  int _hit(Offset p) {
    final list = opts.value;
    int best = -1;
    double bestD = geo.hitRadius;
    for (var i = 0; i < list.length; i++) {
      if (!list[i].enabled) continue;
      final d = (geo.optionCenter(i, 1) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// true = sesi selesai (aksi dijalankan); false = menu tetap terbuka (mode ketuk).
  bool release(Offset p) {
    final i = _hit(p);
    if (i >= 0) {
      _select(i);
      return true;
    }
    tapMode.value = true;
    hoverIndex.value = -1;
    return false;
  }

  void _select(int i) {
    if (_closed) return;
    final o = opts.value[i];
    if (!o.enabled) return;
    HapticFeedback.lightImpact();
    dispose(runAction: false);
    o.run();
  }

  void dispose({required bool runAction}) {
    if (_closed) return;
    _closed = true;
    active = false;
    _entry.remove();
    // ValueNotifier dibuang setelah frame agar overlay yang sedang dibongkar
    // tidak lagi mendengarkan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hoverIndex.dispose();
      opts.dispose();
      finger.dispose();
      tapMode.dispose();
    });
  }
}

// ---------------------------------------------------------------------
// Geometri: menu selalu utuh di dalam layar (adaptif posisi artwork)
// ---------------------------------------------------------------------
class _Geometry {
  _Geometry({required this.center, required this.radius, required this.button, required this.count});
  final Offset center;
  final double radius;
  final double button;
  final int count;

  double get hitRadius => button / 2 + 18;

  /// t = 0..1 (progres animasi mengembang).
  Offset optionCenter(int i, double t) {
    final a = -math.pi / 2 + i * (2 * math.pi / count);
    return center + Offset(math.cos(a), math.sin(a)) * (radius * t);
  }

  static _Geometry fit(Offset anchor, MediaQueryData m, int count) {
    final w = m.size.width;
    final radius = w < 360 ? 82.0 : 94.0;
    const button = 54.0;
    // ruang: ring + setengah tombol + label di bawah + label hover di atas.
    final sideM = radius + button / 2 + 14;
    final topM = m.padding.top + radius + button / 2 + 46;
    final bottomM = m.padding.bottom + radius + button / 2 + 34;
    final cx = anchor.dx.clamp(sideM, math.max(sideM, w - sideM)).toDouble();
    final cy = anchor.dy.clamp(topM, math.max(topM, m.size.height - bottomM)).toDouble();
    return _Geometry(center: Offset(cx, cy), radius: radius, button: button, count: count);
  }
}

// ---------------------------------------------------------------------
// Overlay
// ---------------------------------------------------------------------
class _RadialOverlay extends StatefulWidget {
  const _RadialOverlay({
    required this.track,
    required this.anchor,
    required this.media,
    required this.opts,
    required this.hover,
    required this.finger,
    required this.tapMode,
    required this.onGeometry,
    required this.onSelect,
    required this.onDismiss,
  });

  final Track track;
  final Offset anchor;
  final MediaQueryData media;
  final ValueNotifier<List<_Opt>> opts;
  final ValueNotifier<int> hover;
  final ValueNotifier<Offset> finger;
  final ValueNotifier<bool> tapMode;
  final void Function(_Geometry) onGeometry;
  final void Function(int) onSelect;
  final VoidCallback onDismiss;

  @override
  State<_RadialOverlay> createState() => _RadialOverlayState();
}

class _RadialOverlayState extends State<_RadialOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final _Geometry _geo;

  @override
  void initState() {
    super.initState();
    _geo = _Geometry.fit(widget.anchor, widget.media, widget.opts.value.length);
    widget.onGeometry(_geo);
    _c = AnimationController.unbounded(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        // Spring natural: sedikit overshoot lalu mengendap.
        _c.animateWith(SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 420, damping: 26), 0, 1, 0));
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Backdrop: blur tipis + dimming. Ketuk di luar menu = tutup.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = _c.value.clamp(0.0, 1.0);
                  return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5 * t, sigmaY: 5 * t),
                    child: ColoredBox(color: Colors.black.withValues(alpha: 0.46 * t)),
                  );
                },
              ),
            ),
          ),
          // Artwork di pusat sebagai jangkar visual.
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = _c.value.clamp(0.0, 1.0);
              return Positioned(
                left: _geo.center.dx - 34,
                top: _geo.center.dy - 34,
                width: 68,
                height: 68,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.7 + 0.3 * t,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: LoadImageCached(
                            imageUrl: widget.track.thumbnail.urlLow ?? widget.track.thumbnail.url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Label opsi yang sedang disentuh.
          ValueListenableBuilder<int>(
            valueListenable: widget.hover,
            builder: (_, h, __) {
              final list = widget.opts.value;
              final text = h >= 0 && h < list.length ? list[h].label : widget.track.title;
              return Positioned(
                left: 0,
                right: 0,
                top: _geo.center.dy - _geo.radius - _geo.button / 2 - 40,
                child: IgnorePointer(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: widget.media.size.width - 48),
                      child: LiquidGlass(
                      radius: 20,
                      blur: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Opsi-opsi.
          ValueListenableBuilder<List<_Opt>>(
            valueListenable: widget.opts,
            builder: (_, list, __) => ValueListenableBuilder<int>(
              valueListenable: widget.hover,
              builder: (_, h, __) => AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = _c.value;
                  final tc = t.clamp(0.0, 1.0);
                  return Stack(children: [
                    for (var i = 0; i < list.length; i++)
                      _buildOption(i, list[i], t, tc, h == i, reduce),
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(int i, _Opt o, double t, double tc, bool hovered, bool reduce) {
    final center = _geo.optionCenter(i, reduce ? 1 : t);
    final size = _geo.button;
    final scale = (reduce ? 1.0 : tc) * (hovered ? 1.16 : 1.0);
    return Positioned(
      left: center.dx - 33,
      top: center.dy - size / 2,
      width: 66,
      child: Opacity(
        opacity: (tc * (o.enabled ? 1.0 : 0.38)).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Semantics(
            button: true,
            enabled: o.enabled,
            label: o.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: o.enabled ? () => widget.onSelect(i) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 120),
                    scale: 1.0,
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: LiquidGlass(
                        circle: true,
                        blur: 16,
                        active: hovered,
                        child: Center(
                          child: Icon(
                            o.icon,
                            size: 24,
                            color: hovered
                                ? Default_Theme.onPrimaryContainerColor
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: hovered ? 1 : 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
