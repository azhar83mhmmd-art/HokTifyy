import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/core/models/exported.dart';
import 'package:streambeats/core/models/media_playlist_model.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/utils/load_image.dart';

/// Chip suasana di beranda (gaya Sonara). Ketuk -> membuka pencarian dengan
/// kueri suasana tersebut. "Semua" hanya menandai posisi awal.
class HokMoodChips extends StatefulWidget {
  const HokMoodChips({super.key});

  @override
  State<HokMoodChips> createState() => _HokMoodChipsState();
}

class _HokMoodChipsState extends State<HokMoodChips> {
  static const _moods = <({String label, String query})>[
    (label: 'Energi', query: 'energetic workout hits'),
    (label: 'Santai', query: 'chill santai lagu'),
    (label: 'Fokus', query: 'focus study music'),
    (label: 'Pesta', query: 'party hits dj'),
    (label: 'Galau', query: 'lagu galau indonesia'),
    (label: 'Romantis', query: 'lagu romantis indonesia'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        itemCount: _moods.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final selected = i == 0;
          final label = selected ? 'Semua' : _moods[i - 1].label;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: selected
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    final q = Uri.encodeQueryComponent(_moods[i - 1].query);
                    context.go('/Search?query=$q');
                  },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color:
                    selected ? Default_Theme.accentColor2 : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? Default_Theme.accentColor2
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? const Color(0xFF2E1A66)
                      : Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Pilihan Cepat": grid 2 kolom berisi lagu yang baru diputar. Ketuk
/// langsung memutar dari daftar tersebut.
class HokQuickPicks extends StatelessWidget {
  const HokQuickPicks({
    super.key,
    required this.tracks,
    this.onSeeAll,
    this.title = 'Pilihan Cepat',
  });

  final List<Track> tracks;
  final VoidCallback? onSeeAll;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final picks = tracks.take(8).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onSeeAll,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (onSeeAll != null)
                    Icon(Icons.chevron_right_rounded,
                        size: 26, color: Colors.white.withValues(alpha: 0.55)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: picks.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 64,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, i) => _QuickPickTile(
                track: picks[i],
                onTap: () {
                  HapticFeedback.selectionClick();
                  context
                      .read<StreamBeatsPlayerCubit>()
                      .streambeatsPlayer
                      .loadPlaylist(
                        Playlist(tracks: picks, title: title),
                        idx: i,
                        doPlay: true,
                      );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPickTile extends StatelessWidget {
  const _QuickPickTile({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Default_Theme.surfaceHighColor,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: LoadImageCached(
                imageUrl: track.thumbnail.urlLow ?? track.thumbnail.url,
                fallbackUrl: track.thumbnail.url,
                fit: BoxFit.cover,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
