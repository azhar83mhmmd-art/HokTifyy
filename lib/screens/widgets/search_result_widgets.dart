import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/core/models/exported.dart' hide MediaItem;
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/screens/widgets/more_bottom_sheet.dart';
import 'package:streambeats/utils/load_image.dart';

/// Komponen hasil pencarian bergaya Sonara:
/// kartu "Hasil Teratas", header "Lagu-lagu untuk ..." + "Putar Semua",
/// dan daftar lagu dalam satu wadah membulat dengan garis pemisah.

String _artistNames(Track t) => t.artists.map((a) => a.name).join(', ');

String _formatDuration(BigInt? ms) {
  if (ms == null) return '';
  final total = (ms ~/ BigInt.from(1000)).toInt();
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _thumb(Track t) => t.thumbnail.urlLow ?? t.thumbnail.url;

Future<void> _playAll(BuildContext context, List<Track> tracks,
    {int startIndex = 0}) async {
  HapticFeedback.selectionClick();
  await context
      .read<StreamBeatsPlayerCubit>()
      .streambeatsPlayer
      .updateQueueTracks(tracks, doPlay: true, startIndex: startIndex);
}

/// Kartu besar "Hasil Teratas" dengan latar sampul yang diburamkan.
class SearchTopResultCard extends StatelessWidget {
  final Track track;
  final List<Track> allTracks;
  final String title;
  final String playLabel;
  final String radioLabel;

  const SearchTopResultCard({
    super.key,
    required this.track,
    required this.allTracks,
    this.title = 'Hasil Teratas',
    this.playLabel = 'Mainkan Sekarang',
    this.radioLabel = 'Radio',
  });

  @override
  Widget build(BuildContext context) {
    final duration = _formatDuration(track.durationMs);
    final subtitle = [
      _artistNames(track),
      if (duration.isNotEmpty) duration,
    ].where((e) => e.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Colors.white,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                    child: Opacity(
                      opacity: 0.35,
                      child: Transform.scale(
                        scale: 1.4,
                        child: LoadImageCached(
                          imageUrl: _thumb(track),
                          fallbackUrl: _thumb(track),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Default_Theme.surfaceColor.withValues(alpha: 0.78),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                              width: 92,
                              height: 92,
                              child: LoadImageCached(
                                imageUrl: _thumb(track),
                                fallbackUrl: _thumb(track),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Flexible(
                            child: _PillButton(
                              icon: MingCute.play_fill,
                              label: playLabel,
                              filled: true,
                              onTap: () => _playAll(context, [track]),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _PillButton(
                            icon: MingCute.radio_line,
                            label: radioLabel,
                            filled: false,
                            onTap: () {
                              final idx = allTracks.indexOf(track);
                              _playAll(context, allTracks,
                                  startIndex: idx < 0 ? 0 : idx);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF2E1A66) : Colors.white;
    return Material(
      color: filled
          ? Default_Theme.accentColor2
          : Colors.white.withValues(alpha: 0.05),
      shape: StadiumBorder(
        side: filled
            ? BorderSide.none
            : BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header seksi: judul besar di kiri, tombol "Putar Semua" di kanan.
class SearchSongsHeader extends StatelessWidget {
  final String title;
  final String playAllLabel;
  final List<Track> tracks;

  const SearchSongsHeader({
    super.key,
    required this.title,
    required this.tracks,
    this.playAllLabel = 'Putar Semua',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Default_Theme.accentColor2,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _playAll(context, tracks),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(MingCute.play_fill,
                        size: 16, color: Color(0xFF2E1A66)),
                    const SizedBox(width: 6),
                    Text(
                      playAllLabel,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E1A66),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Daftar lagu dalam satu kartu membulat dengan garis pemisah.
class SearchSongGroup extends StatelessWidget {
  final List<Track> tracks;

  /// Jika diisi, dipakai sebagai aksi ketuk (mis. memutar seluruh daftar).
  final void Function(int index)? onTrackTap;

  const SearchSongGroup({super.key, required this.tracks, this.onTrackTap});

  @override
  Widget build(BuildContext context) {
    final player = context.read<StreamBeatsPlayerCubit>().streambeatsPlayer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Default_Theme.surfaceColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: StreamBuilder<MediaItem?>(
          stream: player.mediaItem,
          builder: (context, snapshot) {
            final currentId = snapshot.data?.id;
            return Column(
              children: [
                for (var i = 0; i < tracks.length; i++) ...[
                  _SongRow(
                    track: tracks[i],
                    isPlaying: currentId == tracks[i].id,
                    onTap: () => onTrackTap != null
                        ? onTrackTap!(i)
                        : _playAll(context, [tracks[i]]),
                    onMore: () => showMoreBottomSheet(context, tracks[i],
                        showSinglePlay: true),
                  ),
                  if (i != tracks.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _SongRow({
    required this.track,
    required this.isPlaying,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPlaying
          ? Default_Theme.accentColor2.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: LoadImageCached(
                    imageUrl: _thumb(track),
                    fallbackUrl: _thumb(track),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color:
                            isPlaying ? Default_Theme.accentColor2 : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(MingCute.music_2_line,
                            size: 15,
                            color: Colors.white.withValues(alpha: 0.55)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _artistNames(track),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
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
                icon: Icon(MingCute.more_1_fill,
                    size: 20, color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Seksi lagu gaya Sonara untuk beranda: judul + tombol "Putar Semua" dan
/// daftar lagu dalam kartu membulat (maksimal [maxItems] baris).
class HomeTrackSection extends StatelessWidget {
  final String title;
  final String playAllLabel;
  final List<Track> tracks;
  final int maxItems;
  final VoidCallback? onTitleTap;
  final void Function(int index) onTrackTap;
  final VoidCallback onPlayAll;

  const HomeTrackSection({
    super.key,
    required this.title,
    required this.tracks,
    required this.onTrackTap,
    required this.onPlayAll,
    this.playAllLabel = 'Putar Semua',
    this.maxItems = 5,
    this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final shown = tracks.take(maxItems).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Default_Theme.accentColor2,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onPlayAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(MingCute.play_fill,
                            size: 15, color: Color(0xFF2E1A66)),
                        const SizedBox(width: 6),
                        Text(
                          playAllLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2E1A66),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SearchSongGroup(tracks: shown, onTrackTap: onTrackTap),
      ],
    );
  }
}
