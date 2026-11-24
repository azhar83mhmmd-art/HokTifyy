import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/core/models/exported.dart';
import 'package:streambeats/core/models/media_playlist_model.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/core/widgets/hok_signature.dart';
import 'package:streambeats/utils/load_image.dart';

/// Kartu sorotan beranda (terinspirasi "Campuran Sorotan Harian" Sonara).
/// Ciri khas Vynora Music: sampul berbentuk lengkung ganda (motif logo) di atas
/// latar blur dari sampul lagu pertama.
class HokDailyMixCard extends StatelessWidget {
  const HokDailyMixCard({super.key, required this.tracks});

  final List<Track> tracks;

  static const _archRadius = BorderRadius.only(
    topLeft: Radius.circular(52),
    topRight: Radius.circular(52),
    bottomLeft: Radius.circular(20),
    bottomRight: Radius.circular(20),
  );

  void _play(BuildContext context, {required bool shuffle}) {
    HapticFeedback.mediumImpact();
    context.read<StreamBeatsPlayerCubit>().streambeatsPlayer.loadPlaylist(
          Playlist(tracks: tracks, title: 'Campuran Harian'),
          idx: 0,
          doPlay: !shuffle,
          shuffling: shuffle,
        );
  }

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    final lead = tracks.first;
    final lowUrl = lead.thumbnail.urlLow ?? lead.thumbnail.url;
    final highUrl = lead.thumbnail.urlHigh ?? lead.thumbnail.url;
    final artists = lead.artists.map((a) => a.name).join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            // Latar: sampul diburamkan + gradien violet gelap.
            Positioned.fill(
              child: Transform.scale(
                scale: 1.6,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
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
                      Default_Theme.primaryContainerColor
                          .withValues(alpha: 0.62),
                      Colors.black.withValues(alpha: 0.78),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const ArchGlyph(size: 18),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'CAMPURAN HARIAN',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.3,
                                  color: Default_Theme.accentColor2
                                      .withValues(alpha: 0.95),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          lead.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: Colors.white,
                          ),
                        ),
                        if (artists.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MixButton(
                              filled: true,
                              icon: MingCute.play_fill,
                              label: 'Putar',
                              onTap: () => _play(context, shuffle: false),
                            ),
                            _MixButton(
                              filled: false,
                              icon: MingCute.shuffle_2_fill,
                              label: 'Acak',
                              onTap: () => _play(context, shuffle: true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Sampul lengkung + garis lengkung kedua di belakangnya.
                  SizedBox(
                    width: 112,
                    height: 142,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 9,
                          top: -8,
                          child: Container(
                            width: 100,
                            height: 134,
                            decoration: BoxDecoration(
                              borderRadius: _archRadius,
                              border: Border.all(
                                color: Default_Theme.accentColor2
                                    .withValues(alpha: 0.45),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 4,
                          child: Container(
                            width: 100,
                            height: 134,
                            decoration: BoxDecoration(
                              borderRadius: _archRadius,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: _archRadius,
                              child: LoadImageCached(
                                imageUrl: highUrl,
                                fallbackUrl: lowUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _MixButton extends StatelessWidget {
  const _MixButton({
    required this.filled,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool filled;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF2E1A66) : Colors.white;
    return Material(
      color: filled
          ? Default_Theme.accentColor2
          : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
