import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:streambeats/services/stats/stats_models.dart';
import 'package:streambeats/services/stats/stats_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum StatsStatus { loading, ready, error, unconfigured }

class StatsState extends Equatable {
  const StatsState({
    this.period = StatsPeriod.all,
    this.status = StatsStatus.loading,
    this.entries = const [],
    this.me,
    this.myUserId,
    this.rankDelta = const {},
    this.refreshing = false,
    this.hasMore = false,
    this.loadingMore = false,
  });

  final StatsPeriod period;
  final StatsStatus status;
  final List<LeaderboardEntry> entries;

  /// Peringkat pengguna sendiri (null jika belum punya durasi pada periode ini).
  final LeaderboardEntry? me;
  final String? myUserId;

  /// userId -> perubahan peringkat sejak snapshot sebelumnya pada periode
  /// yang sama (positif = naik). Hanya tersedia selama sesi aplikasi ini.
  final Map<String, int> rankDelta;
  final bool refreshing;

  /// Masih ada halaman berikutnya di server / sedang memuat halaman berikutnya.
  final bool hasMore;
  final bool loadingMore;

  /// Kartu "peringkat saya" hanya muncul bila saya tidak ada di daftar.
  bool get showOwnCard =>
      me != null && !entries.any((e) => e.userId == me!.userId);

  StatsState copyWith({
    StatsPeriod? period,
    StatsStatus? status,
    List<LeaderboardEntry>? entries,
    LeaderboardEntry? me,
    bool clearMe = false,
    String? myUserId,
    Map<String, int>? rankDelta,
    bool? refreshing,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      StatsState(
        period: period ?? this.period,
        status: status ?? this.status,
        entries: entries ?? this.entries,
        me: clearMe ? null : (me ?? this.me),
        myUserId: myUserId ?? this.myUserId,
        rankDelta: rankDelta ?? this.rankDelta,
        refreshing: refreshing ?? this.refreshing,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  @override
  List<Object?> get props =>
      [period, status, entries, me, myUserId, rankDelta, refreshing, hasMore, loadingMore];
}

/// Leaderboard: ambil data lewat RPC (total tersimpan, bukan hitung ulang
/// histori), diperbarui lewat Realtime (sinyal perubahan) + polling ringan
/// saat halaman terlihat. Tidak menyentuh pemutar musik.
class StatsCubit extends Cubit<StatsState> {
  StatsCubit() : super(const StatsState());

  static const _pollEvery = Duration(seconds: 45);
  static const _minGap = Duration(milliseconds: 1500);
  static const _pageSize = 50;
  static const _maxRows = 500; // batas atas yang dimuat di klien
  final Set<StatsPeriod> _snapshotTouched = {};

  final _repo = StatsRepository.instance;
  final Map<StatsPeriod, Map<String, int>> _lastRanks = {};

  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _poll;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _active = false;
  bool _fetching = false;
  int _generation = 0; // membuang respons periode lama

  Future<void> start() async {
    if (!_repo.available) {
      emit(state.copyWith(status: StatsStatus.unconfigured));
      return;
    }
    try {
      final uid = await _repo.ensureReady();
      emit(state.copyWith(myUserId: uid));
    } catch (_) {
      emit(state.copyWith(status: StatsStatus.error));
      return;
    }
    _channel ??= _repo.subscribeTotals(_onRemoteChange);
    await _fetch();
  }

  /// Dipanggil StatsScreen saat tab terlihat / tersembunyi.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _poll?.cancel();
    if (active) {
      if (state.status != StatsStatus.unconfigured) {
        _poll = Timer.periodic(_pollEvery, (_) => _fetch(silent: true));
        // Kembali ke tab: segarkan bila data sudah agak lama.
        if (DateTime.now().difference(_lastFetch) > const Duration(seconds: 10)) {
          _fetch(silent: true);
        }
      }
    }
  }

  Future<void> setPeriod(StatsPeriod p) async {
    if (p == state.period) return;
    _generation++;
    emit(state.copyWith(
      period: p,
      // Tampilkan data lama secara halus sambil memuat (tanpa reload layar).
      refreshing: true,
      clearMe: true,
      rankDelta: const {},
    ));
    await _fetch(silent: true, force: true);
  }

  Future<void> refresh() => _fetch(silent: true, force: true);

  void _onRemoteChange() {
    if (!_active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => _fetch(silent: true));
  }

  Future<void> _fetch({bool silent = false, bool force = false}) async {
    if (!_repo.available || isClosed) return;
    if (_fetching && !force) return;
    if (!force && DateTime.now().difference(_lastFetch) < _minGap) return;
    _fetching = true;
    final gen = _generation;
    final period = state.period;
    if (!silent) emit(state.copyWith(status: StatsStatus.loading));

    try {
      // Muat ulang sebanyak yang sudah tampil (halaman 1..n) agar posisi
      // tetap konsisten saat data berubah; kelipatan _pageSize, maks _maxRows.
      final want = (state.period == period && state.entries.isNotEmpty)
          ? state.entries.length.clamp(_pageSize, _maxRows)
          : _pageSize;
      final entries = <LeaderboardEntry>[];
      var lastPageFull = false;
      for (var off = 0; off < want; off += _pageSize) {
        final page = await _repo.leaderboard(period, limit: _pageSize, offset: off);
        entries.addAll(page);
        lastPageFull = page.length == _pageSize;
        if (!lastPageFull) break;
      }
      final me = await _repo.myRank(period);
      if (isClosed || gen != _generation) return;

      final delta = _buildDelta(period, entries);
      _lastFetch = DateTime.now();

      emit(StatsState(
        period: period,
        status: StatsStatus.ready,
        entries: entries,
        me: me,
        myUserId: state.myUserId,
        rankDelta: delta,
        hasMore: lastPageFull && entries.length < _maxRows,
      ));
      if (_snapshotTouched.add(period)) {
        unawaited(_repo.touchRankSnapshot(period));
      }
    } catch (_) {
      if (isClosed || gen != _generation) return;
      // Pertahankan data terakhir jika ada; hanya tandai error bila kosong.
      emit(state.copyWith(
        refreshing: false,
        status: state.entries.isEmpty ? StatsStatus.error : StatsStatus.ready,
      ));
    } finally {
      _fetching = false;
    }
  }

  /// Indikator naik/turun: utamakan data server (snapshot harian, tahan
  /// restart); jika belum ada, pakai perbandingan dengan fetch sebelumnya.
  Map<String, int> _buildDelta(StatsPeriod period, List<LeaderboardEntry> entries) {
    final prev = _lastRanks[period];
    final delta = <String, int>{};
    for (final e in entries) {
      int? d;
      if (e.prevRank != null) {
        d = e.prevRank! - e.rank;
      } else if (prev != null && prev[e.userId] != null) {
        d = prev[e.userId]! - e.rank;
      }
      if (d != null && d != 0) delta[e.userId] = d;
    }
    _lastRanks[period] = {for (final e in entries) e.userId: e.rank};
    return delta;
  }

  /// Halaman berikutnya (dipanggil saat daftar discroll mendekati akhir).
  Future<void> loadMore() async {
    if (!_repo.available || isClosed) return;
    if (!state.hasMore || state.loadingMore || _fetching) return;
    final gen = _generation;
    final period = state.period;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repo.leaderboard(period,
          limit: _pageSize, offset: state.entries.length);
      if (isClosed || gen != _generation) return;
      final byId = {for (final e in state.entries) e.userId: e};
      for (final e in page) {
        byId[e.userId] = e; // dedupe jika peringkat bergeser saat paging
      }
      final merged = byId.values.toList()..sort((a, b) => a.rank.compareTo(b.rank));
      emit(state.copyWith(
        entries: merged,
        rankDelta: _buildDelta(period, merged),
        hasMore: page.length == _pageSize && merged.length < _maxRows,
        loadingMore: false,
      ));
    } catch (_) {
      if (!isClosed && gen == _generation) emit(state.copyWith(loadingMore: false));
    }
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    _poll?.cancel();
    final ch = _channel;
    if (ch != null) await _repo.unsubscribe(ch);
    return super.close();
  }
}
