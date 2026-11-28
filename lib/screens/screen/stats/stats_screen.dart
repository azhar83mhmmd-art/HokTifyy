import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:streambeats/blocs/media_player/streambeats_player_cubit.dart';
import 'package:streambeats/blocs/stats/stats_cubit.dart';
import 'package:streambeats/core/constants/route_paths.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/screens/widgets/liquid_glass.dart';
import 'package:streambeats/screens/widgets/stats/podium.dart';
import 'package:streambeats/screens/widgets/stats/user_avatar.dart';
import 'package:streambeats/services/stats/stats_models.dart';
import 'package:streambeats/services/stats/stats_repository.dart';

/// Tab "Stats": Listening Leaderboard.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => StatsCubit()..start(),
      child: const _StatsView(),
    );
  }
}

class _StatsView extends StatefulWidget {
  const _StatsView();

  @override
  State<_StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<_StatsView> {
  bool? _wasActive;
  UserProfile? _me;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // Halaman berikutnya dimuat saat mendekati akhir daftar.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent - p.pixels < 700) {
      context.read<StatsCubit>().loadMore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab di StatefulShellRoute tetap hidup di belakang layar; polling &
    // sinkronisasi hanya berjalan saat tab Stats benar-benar terlihat.
    final active = TickerMode.of(context);
    if (_wasActive == active) return;
    _wasActive = active;
    final cubit = context.read<StatsCubit>();
    cubit.setActive(active);
    if (active) {
      unawaited(_syncOnShow(cubit));
    }
  }

  Future<void> _syncOnShow(StatsCubit cubit) async {
    try {
      // Kirim sesi yang masih tertunda agar durasi terbaru ikut terhitung.
      await context.read<StreamBeatsPlayerCubit>().streambeatsPlayer.flushListeningStats();
    } catch (_) {}
    if (!mounted) return;
    unawaited(cubit.refresh());
    unawaited(_loadMe());
  }

  Future<void> _loadMe() async {
    if (!StatsRepository.instance.available) return;
    try {
      final p = await StatsRepository.instance.profile();
      if (mounted && p != null) setState(() => _me = p);
    } catch (_) {}
  }

  void _openProfile(String? userId) {
    context.pushNamed(
      RoutePaths.profileScreen,
      queryParameters: userId == null ? const {} : {'userId': userId},
    ).then((_) {
      // Profil mungkin berubah: segarkan avatar header + leaderboard.
      if (!mounted) return;
      _loadMe();
      context.read<StatsCubit>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<StatsCubit, StatsState>(
          builder: (context, s) {
            return RefreshIndicator(
              color: Default_Theme.accentColor2,
              backgroundColor: Default_Theme.surfaceHighColor,
              onRefresh: () => context.read<StatsCubit>().refresh(),
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _Header(me: _me, onProfile: () => _openProfile(null))),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _PeriodSelector(
                        value: s.period,
                        onChanged: context.read<StatsCubit>().setPeriod,
                      ),
                    ),
                  ),
                  ..._body(context, s),
                  if (s.loadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Default_Theme.accentColor2),
                          ),
                        ),
                      ),
                    ),
                  // Ruang untuk MorphBar + mini player yang melayang.
                  SliverToBoxAdapter(child: SizedBox(height: 150 + bottomInset)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, StatsState s) {
    switch (s.status) {
      case StatsStatus.unconfigured:
        return [
          const _Message(
            icon: MingCute.cloud_line,
            title: 'Leaderboard unavailable',
            text: 'Cloud features are not configured in this build, so '
                'listening time cannot be ranked yet.',
          ),
        ];
      case StatsStatus.loading:
        return [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 96),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Default_Theme.accentColor2),
                ),
              ),
            ),
          ),
        ];
      case StatsStatus.error:
        return [
          _Message(
            icon: MingCute.wifi_off_line,
            title: 'Couldn\'t load the leaderboard',
            text: 'Check your connection and try again.',
            action: 'Retry',
            onAction: () => context.read<StatsCubit>().refresh(),
          ),
        ];
      case StatsStatus.ready:
        break;
    }

    if (s.entries.isEmpty) {
      return [
        _Message(
          icon: MingCute.headphone_line,
          title: 'No listeners yet',
          text: s.period == StatsPeriod.all
              ? 'The leaderboard will appear once people start listening to music.'
              : 'Nobody has listened ${s.period == StatsPeriod.week ? 'this week' : 'this month'} yet. '
                  'Play a song to take the first spot.',
        ),
      ];
    }

    final top3 = s.entries.where((e) => e.rank <= 3).toList(growable: false);
    final rest = s.entries.where((e) => e.rank > 3).toList(growable: false);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: StatsPodium(top3: top3, onOpen: (e) => _openProfile(e.userId)),
        ),
      ),
      if (rest.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SectionLabel('OTHER RANKINGS')),
        SliverToBoxAdapter(
          child: _RankList(
            entries: rest,
            myUserId: s.myUserId,
            deltas: s.rankDelta,
            onOpen: (e) => _openProfile(e.userId),
          ),
        ),
      ],
      if (s.showOwnCard) ...[
        const SliverToBoxAdapter(child: _SectionLabel('YOUR RANKING')),
        SliverToBoxAdapter(
          child: _RankRow(
            entry: s.me!,
            isMe: true,
            delta: 0,
            onTap: () => _openProfile(s.me!.userId),
          ),
        ),
      ],
    ];
  }
}

// ---------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.me, required this.onProfile});
  final UserProfile? me;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening Leaderboard',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'The most dedicated listeners.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Default_Theme.primaryColor2,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Open your profile',
            child: GestureDetector(
              onTap: onProfile,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: UserAvatar(
                  name: me?.displayName ?? 'You',
                  url: me?.avatarUrl,
                  accent: me?.accentColor,
                  frame: me?.frame ?? 'none',
                  size: 44,
                  borderColor: Colors.white.withValues(alpha: 0.14),
                  borderWidth: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 20, 8),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
      );
}

// ---------------------------------------------------------------------
// Pemilih periode (pil geser)
// ---------------------------------------------------------------------
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});
  final StatsPeriod value;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    const items = StatsPeriod.values;
    final idx = items.indexOf(value);
    return SizedBox(
      height: 42,
      child: LiquidGlass(
      radius: 21,
      blur: 18,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: idx * w,
              width: w,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Default_Theme.primaryContainerColor,
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
            Row(
              children: [
                for (final p in items)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: p == value,
                      label: p.label,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(p),
                        child: Center(
                          child: Text(
                            p.label,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: p == value ? FontWeight.w700 : FontWeight.w500,
                              color: p == value
                                  ? Default_Theme.onPrimaryContainerColor
                                  : Default_Theme.primaryColor2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Daftar peringkat 4+ : tinggi baris tetap + AnimatedPositioned agar
// perpindahan posisi halus (tanpa kedip, tanpa reload halaman).
// ---------------------------------------------------------------------
const double _rowH = 66;

class _RankList extends StatelessWidget {
  const _RankList({
    required this.entries,
    required this.myUserId,
    required this.deltas,
    required this.onOpen,
  });

  final List<LeaderboardEntry> entries;
  final String? myUserId;
  final Map<String, int> deltas;
  final void Function(LeaderboardEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: entries.length * _rowH,
      child: Stack(
        children: [
          for (var i = 0; i < entries.length; i++)
            AnimatedPositioned(
              key: ValueKey(entries[i].userId),
              duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
              curve: Curves.easeInOutCubic,
              top: i * _rowH,
              left: 0,
              right: 0,
              height: _rowH,
              child: RepaintBoundary(
                child: _RankRow(
                  entry: entries[i],
                  isMe: entries[i].userId == myUserId,
                  delta: deltas[entries[i].userId] ?? 0,
                  onTap: () => onOpen(entries[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.entry,
    required this.isMe,
    required this.delta,
    required this.onTap,
  });

  final LeaderboardEntry entry;
  final bool isMe;
  final int delta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Semantics(
      button: true,
      label: 'Peringkat ${e.rank}, ${e.displayName}, ${formatListening(e.totalSeconds)}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: _rowH,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isMe
                ? Default_Theme.primaryContainerColor.withValues(alpha: 0.28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isMe
                ? Border.all(color: Default_Theme.accentColor2.withValues(alpha: 0.25))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${e.rank}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              UserAvatar(
                name: e.displayName,
                url: e.avatarUrl,
                accent: e.accentColor,
                frame: e.frame,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? '${e.displayName} (You)' : e.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (e.username != null)
                      Text(
                        '@${e.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.42),
                        ),
                      ),
                  ],
                ),
              ),
              if (delta != 0) ...[
                _DeltaBadge(delta: delta),
                const SizedBox(width: 8),
              ],
              Text(
                formatListening(e.totalSeconds),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Default_Theme.primaryColor2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});
  final int delta;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final c = up ? Default_Theme.successColor : Colors.white.withValues(alpha: 0.45);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
            size: 22, color: c),
        Text(
          '${delta.abs()}',
          style: TextStyle(
              fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: c),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Empty / error state
// ---------------------------------------------------------------------
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 72, 36, 0),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Default_Theme.surfaceColor,
                border: Border.all(color: Default_Theme.outlineColor),
              ),
              child: Icon(icon, size: 28, color: Default_Theme.accentColor2),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13.5,
                  height: 1.45),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}
