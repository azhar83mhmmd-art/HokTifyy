import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:streambeats/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:streambeats/blocs/library/cubit/library_items_cubit.dart';
import 'package:streambeats/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:streambeats/core/adapters/track_adapter.dart';
import 'package:streambeats/core/widgets/hok_player_widgets.dart';
import 'package:streambeats/screens/screen/home_views/timer_view.dart';
import 'package:streambeats/screens/screen/player_views/equalizer_view.dart';
import 'package:streambeats/screens/widgets/more_bottom_sheet.dart';
import 'package:streambeats/screens/widgets/up_next_panel.dart';
import 'package:streambeats/screens/widgets/volume_slider.dart';
import 'package:streambeats/screens/widgets/media_metadata_links.dart';
import 'package:streambeats/screens/screen/player_views/segments_sheet.dart';
import 'package:streambeats/services/streambeats_player.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:streambeats/l10n/app_localizations.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:streambeats/services/player/player_engine.dart';
import 'package:streambeats/screens/widgets/like_widget.dart';
import 'package:streambeats/screens/widgets/snackbar.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/utils/load_image.dart';
import 'package:streambeats/screens/widgets/artwork_anchors.dart';
import 'package:streambeats/utils/pallete_generator.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../blocs/media_player/streambeats_player_cubit.dart';
import '../../blocs/mini_player/mini_player_cubit.dart';
import 'player_views/fullscreen_lyrics_view.dart';

/// Warna latar bawaan (violet gelap) bila sampul belum punya palet.
const Color _kDefaultTint = Color(0xFF2D2057);

String _fmt(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

class AudioPlayerView extends StatefulWidget {
  const AudioPlayerView({super.key});

  @override
  State<AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<AudioPlayerView> {
  final UpNextPanelController _upNextPanelController = UpNextPanelController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlayerOverlayCubit>().registerUpNextPanelCollapse(
              () => _upNextPanelController.collapse(),
            );
      }
    });
  }

  @override
  void dispose() {
    context.read<PlayerOverlayCubit>().unregisterUpNextPanelCollapse();
    super.dispose();
  }

  void _openLyrics() {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const FullscreenLyricsView(),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final musicPlayer =
        context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    final isMobile = ResponsiveBreakpoints.of(context).smallerOrEqualTo(TABLET);

    Widget playerUi(bool showQueueTab) => _PlayerUI(
          musicPlayer: musicPlayer,
          showQueueTab: showQueueTab,
          onClose: () {
            if (!_upNextPanelController.collapse()) {
              context.read<PlayerOverlayCubit>().hidePlayer();
            }
          },
          onMore: () => showMoreBottomSheet(context, musicPlayer.currentMedia),
          onLyrics: _openLyrics,
          onQueue: () => _upNextPanelController.toggle(),
        );

    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      resizeToAvoidBottomInset: false,
      body: isMobile
          ? LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Positioned.fill(child: playerUi(true)),
                    UpNextPanel(
                      peekHeight: 60.0,
                      parentHeight: constraints.maxHeight,
                      controller: _upNextPanelController,
                    ),
                  ],
                );
              },
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 400,
                    maxWidth: MediaQuery.of(context).size.width * 0.60,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: playerUi(false),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.8,
                      child: UpNextPanel(
                        peekHeight: 60,
                        parentHeight: MediaQuery.of(context).size.height * 0.8,
                        isDesktopMode: true,
                        controller: _upNextPanelController,
                      ),
                    ),
                  ),
                )
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kerangka layar: latar gradien dari sampul + top bar + sampul + kontrol
// ---------------------------------------------------------------------------

class _PlayerUI extends StatefulWidget {
  final StreamBeatsMusicPlayer musicPlayer;
  final bool showQueueTab;
  final VoidCallback onClose;
  final VoidCallback onMore;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  const _PlayerUI({
    required this.musicPlayer,
    required this.showQueueTab,
    required this.onClose,
    required this.onMore,
    required this.onLyrics,
    required this.onQueue,
  });

  @override
  State<_PlayerUI> createState() => _PlayerUIState();
}

class _PlayerUIState extends State<_PlayerUI> {
  Color _tint = _kDefaultTint;
  String? _lastArtUri;
  StreamSubscription? _mediaSub;

  @override
  void initState() {
    super.initState();
    final player = widget.musicPlayer;
    _mediaSub = player.mediaItem.listen((mi) {
      final artUri = mi?.artUri?.toString();
      if (artUri != _lastArtUri) {
        _lastArtUri = artUri;
        _fetchTint(artUri);
      }
    });
    _lastArtUri = player.mediaItem.valueOrNull?.artUri?.toString();
    _fetchTint(_lastArtUri);
  }

  Future<void> _fetchTint(String? artUri) async {
    if (artUri == null || artUri.isEmpty) return;
    try {
      final palette = await getPalleteFromImage(artUri);
      if (!mounted || _lastArtUri != artUri) return;
      final c = palette.vibrantColor?.color ?? palette.dominantColor?.color;
      if (c != null) setState(() => _tint = _toTint(c));
    } catch (_) {}
  }

  /// Ubah warna sampul menjadi warna latar gelap yang tetap terbaca.
  static Color _toTint(Color c) {
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < 0.08) return _kDefaultTint;
    return hsl
        .withSaturation(hsl.saturation.clamp(0.28, 0.65).toDouble())
        .withLightness(0.24)
        .toColor();
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 760;
    return Stack(
      fit: StackFit.expand,
      children: [
        _PlayerBackdrop(tint: _tint, artUri: _lastArtUri),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              _PlayerTopBar(
                showQueueTab: widget.showQueueTab,
                onClose: widget.onClose,
                onMore: widget.onMore,
                onLyrics: widget.onLyrics,
                onQueue: widget.onQueue,
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 42, vertical: 10),
                  child: CoverImageVolSlider(tint: _tint),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: PlayerCtrlWidgets(
                  musicPlayer: widget.musicPlayer,
                  compact: compact,
                ),
              ),
              const SizedBox(height: 72),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerBackdrop extends StatelessWidget {
  final Color tint;
  final String? artUri;
  const _PlayerBackdrop({required this.tint, this.artUri});

  @override
  Widget build(BuildContext context) {
    const base = Default_Theme.themeColor;
    final art = artUri;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tint, Color.lerp(tint, base, 0.62)!, base],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Ambient: sampul diburamkan dan diredam, berganti dengan crossfade.
          if (art != null && art.isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              switchInCurve: Curves.easeOut,
              child: ImageFiltered(
                key: ValueKey(art),
                imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: Opacity(
                  opacity: 0.22,
                  child: Transform.scale(
                    scale: 1.5,
                    child: LoadImageCached(
                      imageUrl: art,
                      fallbackUrl: art,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          // Redam bagian bawah agar kontrol tetap terbaca.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  base.withValues(alpha: 0.55),
                ],
                stops: const [0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerTopBar extends StatelessWidget {
  final bool showQueueTab;
  final VoidCallback onClose;
  final VoidCallback onMore;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  const _PlayerTopBar({
    required this.showQueueTab,
    required this.onClose,
    required this.onMore,
    required this.onLyrics,
    required this.onQueue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = ['Diputar', 'Lirik', if (showQueueTab) l10n.playerQueue];
    final icons = [
      MingCute.music_2_line,
      MingCute.align_center_line,
      if (showQueueTab) MingCute.list_check_3_line,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _RoundIconButton(
              icon: Icons.keyboard_arrow_down_rounded, onTap: onClose),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: HokSegmentedTabs(
                  labels: labels,
                  icons: icons,
                  selectedIndex: 0,
                  onChanged: (i) {
                    if (i == 1) onLyrics();
                    if (i == 2) onQueue();
                  },
                ),
              ),
            ),
          ),
          _RoundIconButton(icon: MingCute.more_2_fill, onTap: onMore),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 24, color: Default_Theme.primaryColor1),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sampul + lengkung gelombang suara (ciri khas Vynora Music)
// ---------------------------------------------------------------------------

class CoverImageVolSlider extends StatelessWidget {
  final Color tint;
  const CoverImageVolSlider({super.key, this.tint = _kDefaultTint});

  @override
  Widget build(BuildContext context) {
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;

    return VolumeDragController(
      child: StreamBuilder<MediaItem?>(
        stream: player.mediaItem,
        builder: (context, snapshot) {
          final currentTrack = player.currentTrackInfo;
          final highResUrl =
              currentTrack.thumbnail.urlHigh ?? currentTrack.thumbnail.url;
          final lowResUrl =
              currentTrack.thumbnail.urlLow ?? currentTrack.thumbnail.url;

          return StreamBuilder<bool>(
            stream: player.engine.playingStream,
            initialData: player.engine.playing,
            builder: (context, playingSnap) {
              final playing = playingSnap.data ?? false;
              return SizedBox.expand(
                child: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: ArtworkAnchors.coverOpacity,
                    builder: (context, o, child) =>
                        Opacity(opacity: o, child: child),
                    child: AspectRatio(
                    aspectRatio: 1.0,
                    child: AnimatedScale(
                      scale: playing ? 1.0 : 0.93,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      child: SoundArcs(
                        isPlaying: playing,
                        child: DecoratedBox(
                          key: ArtworkAnchors.cover,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: tint.withValues(alpha: 0.65),
                                blurRadius: 46,
                                spreadRadius: -6,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: LoadImageCached(
                              imageUrl: highResUrl,
                              fallbackUrl: lowResUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Judul, progress, kontrol, volume, chip
// ---------------------------------------------------------------------------

class PlayerCtrlWidgets extends StatelessWidget {
  final StreamBeatsMusicPlayer musicPlayer;
  final bool compact;
  const PlayerCtrlWidgets(
      {super.key, required this.musicPlayer, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SongInfoRow(),
          const SizedBox(height: 6),
          _PlayerSeek(musicPlayer: musicPlayer),
          const SizedBox(height: 6),
          _MainControls(musicPlayer: musicPlayer),
          const SizedBox(height: 8),
          const _ShuffleLoopRow(),
          if (!compact) const _VolumeRow(),
          SizedBox(height: compact ? 6 : 10),
          _ChipsRow(musicPlayer: musicPlayer),
        ],
      ),
    );
  }
}

class _SongInfoRow extends StatelessWidget {
  const _SongInfoRow();

  @override
  Widget build(BuildContext context) {
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<MediaItem?>(
            stream: player.mediaItem,
            builder: (context, snapshot) {
              final currentTrack = player.currentTrackInfo;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentTrack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        Default_Theme.secondoryTextStyle.merge(const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Default_Theme.primaryColor1,
                    )),
                  ),
                  const SizedBox(height: 3),
                  TrackMetadataLinks(
                    track: currentTrack,
                    showAlbum: currentTrack.album != null,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Default_Theme.secondoryTextStyle.merge(TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Default_Theme.primaryColor1.withValues(alpha: 0.7),
                    )),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        const _DownloadButton(),
        const _LikeButton(),
      ],
    );
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton();

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  String? _lastTrackId;
  bool _isDownloaded = false;
  StreamSubscription? _mediaSub;

  @override
  void initState() {
    super.initState();
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    _mediaSub = player.mediaItem.listen((mi) {
      if (mi?.id != _lastTrackId) {
        _lastTrackId = mi?.id;
        _queryDownloadState(mi);
      }
    });
    _queryDownloadState(player.mediaItem.valueOrNull);
  }

  Future<void> _queryDownloadState(MediaItem? mi) async {
    if (mi == null) {
      if (mounted) setState(() => _isDownloaded = false);
      return;
    }
    try {
      final info = await context
          .read<DownloaderCubit>()
          .getDownloadInfo(mediaItemToTrack(mi));
      if (mounted) setState(() => _isDownloaded = info != null);
    } catch (_) {
      if (mounted) setState(() => _isDownloaded = false);
    }
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDownloaded) return const SizedBox.shrink();
    return Tooltip(
      message: AppLocalizations.of(context)!.tooltipAvailableOffline,
      child: IconButton(
        iconSize: 25,
        icon: Icon(
          Icons.offline_pin_rounded,
          color: Default_Theme.accentColor2.withValues(alpha: 0.8),
        ),
        onPressed: () {},
      ),
    );
  }
}

class _LikeButton extends StatefulWidget {
  const _LikeButton();

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  String? _lastTrackId;
  bool _isLiked = false;
  StreamSubscription? _mediaSub;

  @override
  void initState() {
    super.initState();
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    _mediaSub = player.mediaItem.listen((mi) {
      if (mi?.id != _lastTrackId) {
        _lastTrackId = mi?.id;
        _queryLikedState(mi);
      }
    });
    _queryLikedState(player.mediaItem.valueOrNull);
  }

  Future<void> _queryLikedState(MediaItem? mi) async {
    if (mi == null) {
      if (mounted) setState(() => _isLiked = false);
      return;
    }
    try {
      final liked = await context
          .read<LibraryItemsCubit>()
          .isTrackLiked(mediaItemToTrack(mi));
      if (mounted) setState(() => _isLiked = liked);
    } catch (_) {
      if (mounted) setState(() => _isLiked = false);
    }
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<bool>(
      stream: player.engine.playingStream,
      builder: (context, playingSnapshot) {
        final isPlaying = playingSnapshot.data ?? false;
        final currentMedia = player.mediaItem.valueOrNull;
        if (currentMedia == null) return const SizedBox.shrink();

        return LikeBtnWidget(
          isPlaying: isPlaying,
          isLiked: _isLiked,
          iconSize: 25,
          onLiked: () {
            context
                .read<LibraryItemsCubit>()
                .setTrackLiked(mediaItemToTrack(currentMedia), true);
            setState(() => _isLiked = true);
            SnackbarService.showMessage(l10n.playerLiked(currentMedia.title));
          },
          onDisliked: () {
            context
                .read<LibraryItemsCubit>()
                .setTrackLiked(mediaItemToTrack(currentMedia), false);
            setState(() => _isLiked = false);
            SnackbarService.showMessage(l10n.playerUnliked(currentMedia.title));
          },
        );
      },
    );
  }
}

/// Progress bar bergelombang + waktu + lompat 10 detik (gaya Sonara).
class _PlayerSeek extends StatelessWidget {
  final StreamBeatsMusicPlayer musicPlayer;
  const _PlayerSeek({required this.musicPlayer});

  @override
  Widget build(BuildContext context) {
    final playerCubit = context.read<StreamBeatsPlayerCubit>();
    final labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: Default_Theme.primaryColor1.withValues(alpha: 0.65),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return RepaintBoundary(
      child: StreamBuilder<ProgressBarStreams>(
        stream: playerCubit.progressStreams,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final pos = data?.position ?? Duration.zero;
          final dur = data?.duration ?? Duration.zero;
          final remaining = dur - pos;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WavySeekBar(
                position: pos,
                duration: dur,
                isPlaying: data?.isPlaying ?? false,
                onSeek: playerCubit.streambeatsPlayer.seek,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(pos), style: labelStyle),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SkipSecButton(
                          icon: Icons.replay_10_rounded,
                          onTap: () => musicPlayer
                              .seekNSecBackward(const Duration(seconds: 10)),
                        ),
                        const SizedBox(width: 6),
                        _SkipSecButton(
                          icon: Icons.forward_10_rounded,
                          onTap: () => musicPlayer
                              .seekNSecForward(const Duration(seconds: 10)),
                        ),
                      ],
                    ),
                    Text(dur == Duration.zero ? '--:--' : '-${_fmt(remaining)}',
                        style: labelStyle),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SkipSecButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SkipSecButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 22,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon,
            size: 24, color: Default_Theme.primaryColor1.withValues(alpha: 0.8)),
      ),
    );
  }
}

/// Prev (pil tonal) · Play (pil lebar, berubah bentuk) · Next (pil tonal).
class _MainControls extends StatelessWidget {
  final StreamBeatsMusicPlayer musicPlayer;
  const _MainControls({required this.musicPlayer});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TonalPillButton(
          icon: MingCute.skip_previous_fill,
          onTap: musicPlayer.skipToPrevious,
        ),
        const SizedBox(width: 10),
        _PlayPill(musicPlayer: musicPlayer),
        const SizedBox(width: 10),
        _TonalPillButton(
          icon: MingCute.skip_forward_fill,
          onTap: musicPlayer.skipToNext,
        ),
      ],
    );
  }
}

class _TonalPillButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TonalPillButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: 76,
          height: 68,
          child: Icon(icon, size: 30, color: Default_Theme.primaryColor1),
        ),
      ),
    );
  }
}

class _PlayPill extends StatelessWidget {
  final StreamBeatsMusicPlayer musicPlayer;
  const _PlayPill({required this.musicPlayer});

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF2E1A66);
    return BlocBuilder<MiniPlayerCubit, MiniPlayerState>(
      builder: (context, state) {
        Widget icon;
        VoidCallback? onTap;

        if (state.isLoading || state.isResolving) {
          icon = const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: fg),
          );
        } else if (state.isCompleted) {
          icon = const Icon(FontAwesome.rotate_right_solid,
              key: ValueKey('replay'), color: fg, size: 28);
          onTap = () {
            musicPlayer.seek(Duration.zero);
            musicPlayer.play();
          };
        } else if (state.hasError) {
          icon = const Icon(MingCute.warning_line,
              key: ValueKey('error'), color: fg, size: 30);
          onTap = musicPlayer.play;
        } else if (state.isPlaying) {
          icon = const Icon(FontAwesome.pause_solid,
              key: ValueKey('pause'), color: fg, size: 28);
          onTap = musicPlayer.pause;
        } else {
          icon = const Icon(MingCute.play_fill,
              key: ValueKey('play'), color: fg, size: 34);
          onTap = musicPlayer.play;
        }

        return GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onTap!();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: 124,
            height: 68,
            decoration: BoxDecoration(
              color: Default_Theme.accentColor2,
              // Berubah bentuk: pil penuh saat jeda, persegi-bulat saat main.
              borderRadius: BorderRadius.circular(state.isPlaying ? 24 : 34),
              boxShadow: [
                BoxShadow(
                  color: Default_Theme.accentColor1.withValues(alpha: 0.38),
                  blurRadius: 26,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: icon,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Baris "Acak" (kiri) dan "Ulangi" (kanan) seperti di Sonara.
class _ShuffleLoopRow extends StatelessWidget {
  const _ShuffleLoopRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ShuffleControl(),
        _LoopControl(),
      ],
    );
  }
}

class _LabelPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _LabelPill(
      {required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final color =
        active ? Default_Theme.accentColor2 : Default_Theme.primaryColor1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? Default_Theme.primaryContainerColor.withValues(alpha: 0.7)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: active ? 1 : 0.8)),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: active ? 1 : 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopControl extends StatelessWidget {
  const _LoopControl();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LoopMode>(
      stream: context.read<StreamBeatsPlayerCubit>().streambeatsPlayer.loopMode,
      builder: (context, snapshot) {
        final loopMode = snapshot.data ?? LoopMode.off;
        final l10n = AppLocalizations.of(context)!;
        return PopupMenuButton<int>(
          padding: EdgeInsets.zero,
          itemBuilder: (_) => [
            PopupMenuItem<int>(value: 0, child: Text(l10n.playerLoopOff)),
            PopupMenuItem<int>(value: 1, child: Text(l10n.playerLoopOne)),
            PopupMenuItem<int>(value: 2, child: Text(l10n.playerLoopAll)),
          ],
          child: _LabelPill(
            icon: loopMode == LoopMode.off
                ? MingCute.repeat_line
                : loopMode == LoopMode.one
                    ? MingCute.repeat_one_line
                    : MingCute.repeat_fill,
            label: loopMode == LoopMode.off
                ? 'Ulangi'
                : loopMode == LoopMode.one
                    ? l10n.playerLoopOne
                    : l10n.playerLoopAll,
            active: loopMode != LoopMode.off,
          ),
          onSelected: (value) {
            final player =
                context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
            if (value == 0) player.setLoopMode(LoopMode.off);
            if (value == 1) player.setLoopMode(LoopMode.one);
            if (value == 2) player.setLoopMode(LoopMode.all);
          },
        );
      },
    );
  }
}

class _ShuffleControl extends StatelessWidget {
  const _ShuffleControl();

  @override
  Widget build(BuildContext context) {
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<bool>(
      stream: player.shuffleMode,
      builder: (context, snapshot) {
        final isShuffle = snapshot.data ?? false;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            player.shuffle(!isShuffle);
          },
          child: _LabelPill(
            icon: MingCute.shuffle_2_fill,
            label: l10n.tooltipShuffle,
            active: isShuffle,
          ),
        );
      },
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context) {
    final engine =
        context.read<StreamBeatsPlayerCubit>().streambeatsPlayer.engine;
    return StreamBuilder<double>(
      stream: engine.volumeStream,
      initialData: engine.volume,
      builder: (context, snapshot) {
        final v = (snapshot.data ?? 1.0).clamp(0.0, 1.0).toDouble();
        return Row(
          children: [
            Icon(Icons.volume_down_rounded,
                size: 20,
                color: Default_Theme.primaryColor1.withValues(alpha: 0.7)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: Default_Theme.accentColor2,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                  thumbColor: Default_Theme.accentColor2,
                ),
                child: Slider(
                  value: v,
                  onChanged: (nv) => engine.setVolume(nv),
                ),
              ),
            ),
            Icon(Icons.volume_up_rounded,
                size: 20,
                color: Default_Theme.primaryColor1.withValues(alpha: 0.7)),
          ],
        );
      },
    );
  }
}

/// Chip aksi: EQ · Timer tidur · Kecepatan · Segmen · Tautan.
class _ChipsRow extends StatelessWidget {
  final StreamBeatsMusicPlayer musicPlayer;
  const _ChipsRow({required this.musicPlayer});

  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static String _speedLabel(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}x' : '${v}x';

  @override
  Widget build(BuildContext context) {
    final engine = musicPlayer.engine;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HokPillChip(
            icon: Icons.graphic_eq_rounded,
            label: 'EQ',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EqualizerView())),
          ),
          const SizedBox(width: 8),
          HokPillChip(
            icon: MingCute.alarm_1_line,
            label: 'Tidur',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const TimerView())),
          ),
          const SizedBox(width: 8),
          StreamBuilder<double>(
            stream: engine.speedStream,
            initialData: engine.speed,
            builder: (context, snapshot) {
              final speed = snapshot.data ?? 1.0;
              return PopupMenuButton<double>(
                padding: EdgeInsets.zero,
                tooltip: '',
                onSelected: (v) => engine.setSpeed(v),
                itemBuilder: (_) => [
                  for (final s in _speeds)
                    PopupMenuItem<double>(
                      value: s,
                      child: Text(_speedLabel(s)),
                    ),
                ],
                child: HokPillChip(
                  icon: Icons.speed_rounded,
                  label: _speedLabel(speed),
                  highlighted: speed != 1.0,
                  trailing: Icon(Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.7)),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          HokPillChip(
            icon: MingCute.list_check_3_line,
            label: 'Segmen',
            onTap: () {
              final mi = musicPlayer.mediaItem.valueOrNull;
              if (mi != null) {
                showSegmentsSheet(
                  context,
                  trackId: mi.id,
                  trackDuration: mi.duration ?? Duration.zero,
                  onSeek: (pos) => musicPlayer.seek(pos),
                );
              }
            },
          ),
          const SizedBox(width: 8),
          HokPillChip(
            icon: MingCute.external_link_line,
            onTap: () async {
              final url = musicPlayer.currentTrackInfo.url;
              if (url != null) {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              } else if (context.mounted) {
                SnackbarService.showMessage(
                    AppLocalizations.of(context)!.snackbarCouldNotOpenLink);
              }
            },
          ),
        ],
      ),
    );
  }
}
