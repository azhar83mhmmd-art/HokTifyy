import 'package:flutter/material.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/screens/widgets/stats/user_avatar.dart';
import 'package:streambeats/services/stats/stats_models.dart';

/// Emas / silver / bronze: HANYA dipakai di podium.
const _gold = Color(0xFFD9B45A);
const _silver = Color(0xFFBFC3CC);
const _bronze = Color(0xFFB87C4B);

Color _medal(int rank) => switch (rank) { 1 => _gold, 2 => _silver, _ => _bronze };

/// Podium horizontal 2 - 1 - 3. Peringkat 1 di tengah, paling tinggi.
/// Slot kosong ditampilkan sebagai blok redup (bukan data palsu).
class StatsPodium extends StatelessWidget {
  const StatsPodium({super.key, required this.top3, required this.onOpen});

  /// Daftar ber-urut peringkat (panjang 0..3).
  final List<LeaderboardEntry> top3;
  final void Function(LeaderboardEntry) onOpen;

  LeaderboardEntry? _at(int rank) {
    for (final e in top3) {
      if (e.rank == rank) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Proporsional di layar sempit maupun lebar.
      final w = c.maxWidth.clamp(280.0, 560.0);
      final k = (w / 360).clamp(0.78, 1.25);
      final heights = {1: 128.0 * k, 2: 100.0 * k, 3: 78.0 * k};
      final avatar = {1: 84.0 * k, 2: 64.0 * k, 3: 64.0 * k};

      Widget col(int rank, double flex) => Expanded(
            flex: (flex * 100).round(),
            child: _PodiumColumn(
              rank: rank,
              entry: _at(rank),
              podiumHeight: heights[rank]!,
              avatarSize: avatar[rank]!,
              onOpen: onOpen,
            ),
          );

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              col(2, 1.0),
              const SizedBox(width: 8),
              col(1, 1.12),
              const SizedBox(width: 8),
              col(3, 1.0),
            ],
          ),
        ),
      );
    });
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.rank,
    required this.entry,
    required this.podiumHeight,
    required this.avatarSize,
    required this.onOpen,
  });

  final int rank;
  final LeaderboardEntry? entry;
  final double podiumHeight;
  final double avatarSize;
  final void Function(LeaderboardEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _medal(rank);
    final e = entry;
    final reduce = MediaQuery.disableAnimationsOf(context);

    final block = Container(
      height: podiumHeight,
      width: double.infinity,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: e == null ? 0.06 : 0.20),
            Default_Theme.surfaceColor.withValues(alpha: 0.0),
          ],
        ),
        border: Border(
          top: BorderSide(color: color.withValues(alpha: e == null ? 0.25 : 0.85), width: 1.5),
          left: BorderSide(color: color.withValues(alpha: 0.10)),
          right: BorderSide(color: color.withValues(alpha: 0.10)),
        ),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: rank == 1 ? 30 : 24,
          fontWeight: FontWeight.w800,
          height: 1,
          color: color.withValues(alpha: e == null ? 0.35 : 1),
        ),
      ),
    );

    if (e == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: avatarSize * 0.5),
        block,
      ]);
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1) ...[
          CustomPaint(size: const Size(26, 18), painter: _CrownPainter(_gold)),
          const SizedBox(height: 4),
        ],
        UserAvatar(
          name: e.displayName,
          url: e.avatarUrl,
          size: avatarSize,
          accent: e.accentColor,
          frame: e.frame,
          borderColor: color,
          borderWidth: 2.5,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            e.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.white,
              fontSize: rank == 1 ? 14.5 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatListening(e.totalSeconds),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Default_Theme.primaryColor2.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 10),
        block,
      ],
    );

    return TweenAnimationBuilder<double>(
      key: ValueKey('podium_${e.userId}'),
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: Semantics(
        button: true,
        label: 'Peringkat $rank, ${e.displayName}, ${formatListening(e.totalSeconds)}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpen(e),
          child: content,
        ),
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  _CrownPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.30)
      ..lineTo(w * 0.25, h * 0.62)
      ..lineTo(w * 0.5, 0)
      ..lineTo(w * 0.75, h * 0.62)
      ..lineTo(w, h * 0.30)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, h - 3, w, 3), const Radius.circular(1.5)),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.color != color;
}
