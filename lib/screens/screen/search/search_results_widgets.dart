import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/core/models/exported.dart' hide MediaItem;
import 'package:streambeats/core/models/media_playlist_model.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/screens/screen/search/vibes_browse.dart'
    show SearchTexts;
import 'package:streambeats/screens/widgets/more_bottom_sheet.dart';
import 'package:streambeats/utils/load_image.dart';

/// Hasil pencarian bergaya Sonara: kartu "Hasil Teratas" + daftar lagu
/// dalam satu kartu membulat dengan tombol "Putar Semua".

String formatTrackDuration(BigInt? ms) {
  if (ms == null) return '';
  final totalSec = ms.toInt() ~/ 1000;
  if (totalSec <= 0) return '';
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _artistsOf(Track t) => t.artists.map((a) => a.name).join(', ');

/// Judul bagian (mis. "Hasil Teratas", "Album") dengan aksesori opsional.
class SearchSectionHeader extends StatelessWidget {
  const SearchSectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Tombol pil terisi (aksen) — dipakai "Putar Semua" & "Mainkan Sekarang".
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = true,
    this.height = 44,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = filled
        ? const Color(0xFF2E1A66)
        : Default_Theme.primaryColor1.withValues(alpha: 0.95);
    return Material(
      color: filled
          ? Default_Theme.accentColor2
          : Colors.white.withValues(alpha: 0.07),
      shape: StadiumBorder(
        side: filled
            ? BorderSide.none
            : BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 20,
                    color: filled ? fg : Default_Theme.accentColor2),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol "Putar Semua" untuk header daftar lagu.
class SearchPlayAllButton extends StatelessWidget {
  const SearchPlayAllButton(
      {super.key, required this.tracks, required this.queueTitle});
  final List<Track> tracks;
  final String queueTitle;

  @override
  Widget build(BuildContext context) {
    return _PillButton(
      label: SearchTexts.of(context).playAll,
      icon: Icons.play_arrow_rounded,
      height: 42,
      onTap: () {
        if (tracks.isEmpty) return;
        context.read<StreamBeatsPlayerCubit>().streambeatsPlayer.loadPlaylist(
              Playlist(tracks: tracks, title: queueTitle),
              idx: 0,
              doPlay: true,
            );
      },
    );
  }
}

/// Kartu "Hasil Teratas": sampul besar, judul, artis · durasi, serta
/// tombol Mainkan Sekarang + Radio.
class SearchTopResultCard extends StatelessWidget {
  const SearchTopResultCard({
    super.key,
    required this.track,
    required this.queue,
    required this.queueTitle,
  });

  final Track track;
  final List<Track> queue;
  final String queueTitle;

  void _playNow(BuildContext context) {
    final idx = queue.indexWhere((t) => t.id == track.id);
    context.read<StreamBeatsPlayerCubit>().streambeatsPlayer.loadPlaylist(
          Playlist(tracks: queue, title: queueTitle),
          idx: idx >= 0 ? idx : 0,
          doPlay: true,
        );
  }

  /// Radio = antrean berisi 1 lagu ini; lagu berikutnya otomatis diisi
  /// mesin rekomendasi (lagu terkait) oleh pemutar.
  void _startRadio(BuildContext context) {
    context
        .read<StreamBeatsPlayerCubit>()
        .streambeatsPlayer
        .updateQueueTracks([track], doPlay: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = SearchTexts.of(context);
    final lowUrl = track.thumbnail.urlLow ?? track.thumbnail.url;
    final coverUrl = track.thumbnail.urlHigh ?? track.thumbnail.url;
    final dur = formatTrackDuration(track.durationMs);
    final subtitle = [_artistsOf(track), if (dur.isNotEmpty) dur]
        .where((e) => e.isNotEmpty)
        .join(' \u00B7 ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.scale(
                scale: 1.6,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                  child: LoadImageCached(imageUrl: lowUrl, fit: BoxFit.cover),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Default_Theme.surfaceColor.withValues(alpha: 0.80),
                      Default_Theme.surfaceColor.withValues(alpha: 0.93),
                    ],
                  ),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 0.8),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _playNow(context),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            width: 104,
                            height: 104,
                            child: LoadImageCached(
                              imageUrl: coverUrl,
                              fallbackUrl: lowUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 26,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white.withValues(alpha: 0.68),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _PillButton(
                          label: t.playNow,
                          icon: Icons.play_arrow_rounded,
                          height: 54,
                          onTap: () => _playNow(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: _PillButton(
                          label: t.radio,
                          icon: Icons.sensors_rounded,
                          filled: false,
                          height: 54,
                          onTap: () => _startRadio(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Daftar lagu dalam SATU kartu membulat (sudut atas pada baris pertama,
/// sudut bawah pada baris terakhir) — lazy, aman untuk hasil panjang.
class SearchTrackGroupSliver extends StatelessWidget {
  const SearchTrackGroupSliver({super.key, required this.tracks});
  final List<Track> tracks;

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = tracks[index];
            final isFirst = index == 0;
            final isLast = index == tracks.length - 1;
            return ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(isFirst ? _radius : 0),
                bottom: Radius.circular(isLast ? _radius : 0),
              ),
              child: _SearchTrackRow(
                track: track,
                showDivider: !isLast,
                playerMediaItem: player.mediaItem,
                onTap: () => player.updateQueueTracks([track], doPlay: true),
                onMore: () =>
                    showMoreBottomSheet(context, track, showSinglePlay: true),
              ),
            );
          },
          childCount: tracks.length,
        ),
      ),
    );
  }
}

class _SearchTrackRow extends StatelessWidget {
  const _SearchTrackRow({
    required this.track,
    required this.showDivider,
    required this.playerMediaItem,
    required this.onTap,
    required this.onMore,
  });

  final Track track;
  final bool showDivider;
  final Stream<MediaItem?> playerMediaItem;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: playerMediaItem,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.id == track.id;
        return Material(
          color: isPlaying
              ? Color.alphaBlend(
                  Default_Theme.primaryContainerColor.withValues(alpha: 0.45),
                  Default_Theme.surfaceColor)
              : Default_Theme.surfaceColor,
          child: InkWell(
            onTap: onTap,
            onLongPress: onMore,
            child: Container(
              decoration: BoxDecoration(
                border: showDivider
                    ? Border(
                        bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06)))
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: LoadImageCached(
                        imageUrl: track.thumbnail.urlLow ?? track.thumbnail.url,
                        fallbackUrl: track.thumbnail.url,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: isPlaying
                                ? Default_Theme.accentColor2
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(MingCute.music_2_line,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.5)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _artistsOf(track),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: Colors.white.withValues(alpha: 0.62),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onMore,
                    icon: Icon(Icons.more_horiz_rounded,
                        color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
