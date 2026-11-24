import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:streambeats/src/rust/api/plugin/commands.dart' show ContentSearchFilter;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:streambeats/blocs/search_suggestions/search_suggestion_bloc.dart';
import 'package:streambeats/core/theme/app_theme.dart';

/// Teks khusus layar pencarian 2.0 (Indonesia + Inggris sebagai cadangan).
/// Sengaja dipisah dari l10n agar tidak perlu generate ulang file terjemahan.
class SearchTexts {
  final bool _id;
  const SearchTexts._(this._id);

  factory SearchTexts.of(BuildContext context) =>
      SearchTexts._(Localizations.localeOf(context).languageCode == 'id');

  String _t(String id, String en) => _id ? id : en;

  String get vibes => _t('Getaran', 'Vibes');
  String get moreMoods =>
      _t('Lebih Banyak Suasana & Wilayah', 'More Moods & Regions');
  String get recentSearches => _t('Pencarian Terbaru', 'Recent Searches');
  String get clear => _t('Hapus', 'Clear');
  String get online => 'Online';
  String get localLibrary => _t('Perpustakaan Lokal', 'Local Library');
  String get hint =>
      _t('Cari lagu, artis, album...', 'Search songs, artists, albums...');
  String get backToVibes => _t('Kembali ke Getaran', 'Back to Vibes');
  String get sources => _t('SUMBER', 'SOURCES');
  String get topResult => _t('Hasil Teratas', 'Top Result');
  String get playNow => _t('Mainkan Sekarang', 'Play Now');
  String get playAll => _t('Putar Semua', 'Play All');
  String songsFor(String q) =>
      _t('Lagu-lagu untuk “ $q ”', 'Songs for “ $q ”');
  String filterLabel(ContentSearchFilter f) {
    switch (f) {
      case ContentSearchFilter.all:
        return _t('Semua', 'All');
      case ContentSearchFilter.track:
        return _t('Lagu', 'Songs');
      case ContentSearchFilter.album:
        return 'Album';
      case ContentSearchFilter.artist:
        return _t('Artis', 'Artists');
      case ContentSearchFilter.playlist:
        return 'Playlist';
    }
  }
}

class _VibeSpec {
  final String key;
  final String labelId;
  final String labelEn;
  final String query;
  final Color color;
  final double height;
  final bool compact;
  final IconData icon;
  final double seed;

  const _VibeSpec(this.key, this.labelId, this.labelEn, this.query, this.color,
      this.height, this.compact, this.icon, this.seed);

  String get image => 'assets/vibes/$key.jpg';
}

class _MoodSpec {
  final String labelId;
  final String labelEn;
  final String query;
  final Color color;
  const _MoodSpec(this.labelId, this.labelEn, this.query, this.color);
}

const List<_VibeSpec> _leftVibes = [
  _VibeSpec('hiphop', 'Hip Hop & Rap', 'Hip Hop & Rap', 'Hip Hop Rap Hits',
      Color(0xFF9E7BFF), 178, false, MingCute.microphone_fill, 0.4),
  _VibeSpec('pop', 'Pop', 'Pop', 'Pop Top Hits', Color(0xFFF6D04D), 282, false,
      MingCute.star_fill, 1.7),
  _VibeSpec('chill', 'Santai', 'Chill', 'Chill Lofi Relax Music',
      Color(0xFF36B5B0), 104, true, MingCute.flower_4_fill, 2.9),
];

const List<_VibeSpec> _rightVibes = [
  _VibeSpec('electronic', 'Elektronik', 'Electronic',
      'Electronic Dance EDM Hits', Color(0xFFF25C9B), 272, false,
      Icons.graphic_eq_rounded, 3.6),
  _VibeSpec('rnb', 'R&B', 'R&B', 'R&B Soul Smooth Hits', Color(0xFF4DA3FF), 104,
      true, MingCute.airpods_fill, 4.4),
  _VibeSpec('party', 'Pesta', 'Party', 'Party Club Dance Anthems',
      Color(0xFFF08A5D), 192, false, Icons.celebration_rounded, 5.2),
];

const List<_MoodSpec> _moods = [
  _MoodSpec('Pop Indonesia', 'Indonesian Pop', 'Pop Indonesia Terbaru',
      Color(0xFFF59E0B)),
  _MoodSpec('K-Pop & J-Pop', 'K-Pop & J-Pop', 'K-Pop J-Pop Viral Hits',
      Color(0xFFEC4899)),
  _MoodSpec('Indie Akustik', 'Indie Acoustic', 'Indie Acoustic Folk Chill',
      Color(0xFF10B981)),
  _MoodSpec('Gas Olahraga', 'Workout Boost', 'Workout Gym Phonk EDM',
      Color(0xFFEF4444)),
  _MoodSpec('Nyetir Malam', 'Late Night Drive', 'Synthwave Night Drive Music',
      Color(0xFF8B5CF6)),
  _MoodSpec('Fokus & Belajar', 'Focus & Study', 'Lo-Fi Study Beats Instrumental',
      Color(0xFF06B6D4)),
];

/// Beranda pencarian "Getaran": kartu suasana bergaya masonry, panel suasana
/// tambahan, dan riwayat pencarian. Tanpa foto — seni kontur bergelombang
/// digambar langsung (ringan, tidak menambah ukuran APK).
class VibesBrowse extends StatefulWidget {
  final void Function(String query) onVibeTap;
  final void Function(String query) onRecentTap;
  final VoidCallback onClearHistory;

  const VibesBrowse({
    super.key,
    required this.onVibeTap,
    required this.onRecentTap,
    required this.onClearHistory,
  });

  @override
  State<VibesBrowse> createState() => _VibesBrowseState();
}

class _VibesBrowseState extends State<VibesBrowse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 16))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<String> _history(SearchSuggestionState s) => s.dbSuggestionList
      .map((e) => e['query'] ?? (e.values.isNotEmpty ? e.values.first : ''))
      .where((q) => q.trim().isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final t = SearchTexts.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlocBuilder<SearchSuggestionBloc, SearchSuggestionState>(
            builder: (context, state) {
              final history = _history(state).take(3).toList();
              return Row(
                children: [
                  Text(
                    t.vibes,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        reverse: false,
                        physics: const BouncingScrollPhysics(),
                        itemCount: history.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) => _HistoryChip(
                          term: history[i],
                          compact: true,
                          onTap: () => widget.onRecentTap(history[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final colW = (c.maxWidth - gap) / 2;
              final scale = (colW / 170).clamp(0.8, 1.5);
              Widget column(List<_VibeSpec> list, int offset) {
                return Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const SizedBox(height: gap),
                      _VibeCard(
                        spec: list[i],
                        height: list[i].height * scale,
                        animation: _ctrl,
                        label: SearchTexts.of(context)._id
                            ? list[i].labelId
                            : list[i].labelEn,
                        flip: (i + offset).isOdd,
                        onTap: () => widget.onVibeTap(list[i].query),
                      ),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: column(_leftVibes, 0)),
                  const SizedBox(width: gap),
                  Expanded(child: column(_rightVibes, 1)),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _MoodsPanel(onTap: widget.onVibeTap),
          BlocBuilder<SearchSuggestionBloc, SearchSuggestionState>(
            builder: (context, state) {
              final history = _history(state);
              if (history.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.recentSearches,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: widget.onClearHistory,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                children: [
                                  Icon(MingCute.delete_2_line,
                                      size: 16,
                                      color: Colors.white.withValues(alpha: 0.6)),
                                  const SizedBox(width: 4),
                                  Text(
                                    t.clear,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final term in history)
                            _HistoryChip(
                              term: term,
                              compact: false,
                              onTap: () => widget.onRecentTap(term),
                            ),
                        ],
                      ),
                    ],
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

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Default_Theme.surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: child,
    );
  }
}

class _MoodsPanel extends StatelessWidget {
  final void Function(String query) onTap;
  const _MoodsPanel({required this.onTap});

  static const _shapes = <BorderRadius>[
    BorderRadius.only(
      topLeft: Radius.circular(22),
      topRight: Radius.circular(10),
      bottomLeft: Radius.circular(10),
      bottomRight: Radius.circular(22),
    ),
    BorderRadius.only(
      topLeft: Radius.circular(10),
      topRight: Radius.circular(22),
      bottomLeft: Radius.circular(22),
      bottomRight: Radius.circular(10),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = SearchTexts.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(MingCute.sparkles_2_line,
                  size: 18, color: Default_Theme.accentColor2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.moreMoods,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _moods.length; i++)
                    SizedBox(
                      width: w,
                      child: _MoodTile(
                        label: SearchTexts.of(context)._id
                            ? _moods[i].labelId
                            : _moods[i].labelEn,
                        color: _moods[i].color,
                        shape: _shapes[((i ~/ 2) + i) % 2],
                        onTap: () => onTap(_moods[i].query),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  final String label;
  final Color color;
  final BorderRadius shape;
  final VoidCallback onTap;

  const _MoodTile({
    required this.label,
    required this.color,
    required this.shape,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: shape,
      child: InkWell(
        borderRadius: shape,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.55), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(MingCute.play_fill,
                  size: 14, color: Colors.white.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String term;
  final bool compact;
  final VoidCallback onTap;

  const _HistoryChip(
      {required this.term, required this.compact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(compact ? 16 : 14),
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(maxWidth: compact ? 120 : 260),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(compact ? 16 : 14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MingCute.history_line,
                size: compact ? 13 : 15,
                color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                term,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VibeCard extends StatefulWidget {
  final _VibeSpec spec;
  final double height;
  final Animation<double> animation;
  final String label;
  final bool flip;
  final VoidCallback onTap;

  const _VibeCard({
    required this.spec,
    required this.height,
    required this.animation,
    required this.label,
    required this.flip,
    required this.onTap,
  });

  @override
  State<_VibeCard> createState() => _VibeCardState();
}

class _VibeCardState extends State<_VibeCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    // Sudut miring bergantian: ciri khas kartu Vynora Music.
    final radius = widget.flip
        ? const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(28),
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(12),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(28),
          );

    final blobCenter = s.compact ? const Offset(0.82, 0.52) : const Offset(0.62, 0.72);

    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.965 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1D1D21),
                Color.alphaBlend(
                    s.color.withValues(alpha: 0.22), const Color(0xFF101014)),
              ],
            ),
            border: Border.all(color: s.color.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: s.color.withValues(alpha: _down ? 0.30 : 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  s.image,
                  fit: BoxFit.cover,
                  alignment:
                      s.compact ? Alignment.centerRight : Alignment.bottomCenter,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) =>
                      _fallbackArt(s, blobCenter),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: s.compact
                            ? Alignment.centerLeft
                            : Alignment.topCenter,
                        end: s.compact
                            ? Alignment.centerRight
                            : Alignment.center,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                if (s.compact)
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    right: 84,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _label(widget.label),
                    ),
                  )
                else
                  Positioned(
                    left: 16,
                    top: 14,
                    right: 16,
                    child: _label(widget.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Cadangan bila foto gagal dimuat: seni kontur digambar langsung.
  Widget _fallbackArt(_VibeSpec s, Offset blobCenter) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _VibePainter(
                animation: widget.animation,
                color: s.color,
                seed: s.seed,
                compact: s.compact,
                center: blobCenter,
              ),
            ),
          ),
          Align(
            alignment: Alignment(blobCenter.dx * 2 - 1, blobCenter.dy * 2 - 1),
            child: Icon(s.icon,
                size: s.compact ? 22 : 30, color: const Color(0xFF14121C)),
          ),
        ],
      );

  Widget _label(String text) => Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: Colors.white,
          shadows: [Shadow(color: Color(0xA6000000), blurRadius: 4)],
        ),
      );
}

/// Seni kontur: cincin bergelombang + piringan hitam + bar equalizer kecil.
class _VibePainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  final double seed;
  final bool compact;
  final Offset center; // pecahan 0..1 dari ukuran kartu

  _VibePainter({
    required this.animation,
    required this.color,
    required this.seed,
    required this.compact,
    required this.center,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * 2 * math.pi;
    final c = Offset(size.width * center.dx, size.height * center.dy);
    final maxR = compact ? size.height * 1.05 : size.width * 0.95;
    final rings = compact ? 9 : 14;
    const steps = 72;

    for (var i = 0; i < rings; i++) {
      final k = i / (rings - 1);
      final base = maxR * (0.30 + 0.70 * k);
      final amp = base * 0.065;
      final path = Path();
      for (var s = 0; s <= steps; s++) {
        final a = s / steps * 2 * math.pi;
        final r = base +
            amp * math.sin(3 * a + phase + seed + i * 0.45) +
            amp * 0.6 * math.sin(5 * a - phase * 0.5 + seed * 2);
        final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        if (s == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.62 * (1 - k * 0.82)),
      );
    }

    // Piringan utama (blob) berwarna terang.
    final blobR = maxR * 0.27;
    final blob = Path();
    for (var s = 0; s <= steps; s++) {
      final a = s / steps * 2 * math.pi;
      final r = blobR *
          (1 + 0.07 * math.sin(3 * a + phase * 1.5 + seed) +
              0.04 * math.sin(2 * a - phase));
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (s == 0) {
        blob.moveTo(p.dx, p.dy);
      } else {
        blob.lineTo(p.dx, p.dy);
      }
    }
    blob.close();
    canvas.drawPath(
      blob,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(color, Colors.white, 0.35)!,
            color,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: blobR * 1.1)),
    );

    // Bar equalizer kecil di kiri bawah (hanya kartu besar).
    if (!compact) {
      const bars = 4;
      for (var i = 0; i < bars; i++) {
        final h = 6 + 12 * (0.5 + 0.5 * math.sin(phase * 3 + i * 1.3 + seed));
        final x = 16.0 + i * 7;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 16 - h, 4, h),
          const Radius.circular(2),
        );
        canvas.drawRRect(
            rect, Paint()..color = color.withValues(alpha: 0.9));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VibePainter old) =>
      old.color != color ||
      old.seed != seed ||
      old.compact != compact ||
      old.center != center;
}
