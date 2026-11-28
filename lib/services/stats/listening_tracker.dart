import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random, min;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:streambeats/core/models/exported.dart';
import 'package:streambeats/services/player/player_engine.dart';
import 'package:streambeats/services/stats/stats_repository.dart';

/// Mencatat durasi mendengarkan yang BENAR-BENAR diputar.
///
/// Sumber kebenaran adalah event [PlayerEngine] (playing + state). Waktu hanya
/// bertambah selama `engine.playing && state == ready` (buffering, pause,
/// loading, dan idle tidak dihitung). Durasi diukur dengan [Stopwatch]
/// (monotonic), bukan selisih jam dinding, sehingga ubah jam perangkat tidak
/// memengaruhi hasil. Event yang terpanggil berulang aman karena [_evaluate]
/// idempoten.
///
/// Sesi dipecah per lagu dan per checkpoint [_checkpointEvery]. Setiap sesi
/// punya UUID, ditaruh di antrean lokal (file JSON) lalu dikirim ke RPC
/// `record_listening_session`. Server memvalidasi & menolak kiriman ganda,
/// sehingga mengirim ulang sesi yang sama tidak menambah durasi.
class ListeningTracker with WidgetsBindingObserver {
  ListeningTracker(this._engine, this._getCurrentTrack) {
    _stateSub = _engine.stateStream.listen((_) => _evaluate());
    _playingSub = _engine.playingStream.listen((_) => _evaluate());
    _completeSub = _engine.completionStream.listen((_) => _finish('completed'));
    WidgetsBinding.instance.addObserver(this);
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) _scheduleSend();
    });
    unawaited(_loadPending().then((_) => _scheduleSend()));
  }

  final PlayerEngine _engine;
  final Track? Function() _getCurrentTrack;

  static const _minSessionSeconds = 3;
  static const _checkpointEvery = Duration(seconds: 60);
  static const _idleFlushAfter = Duration(seconds: 45);
  static const _maxPending = 500;
  static const _maxAge = Duration(days: 2); // server menolak sesi > 3 hari

  StreamSubscription<EngineState>? _stateSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // --- sesi berjalan ---
  String? _sessionId;
  String? _trackId;
  String? _trackTitle;
  DateTime? _startedAt;
  DateTime? _lastActiveAt;
  int _accumMs = 0;
  final Stopwatch _sw = Stopwatch();
  bool _running = false;
  Timer? _checkpointTimer;
  Timer? _idleTimer;

  // --- antrean kirim ---
  final List<Map<String, dynamic>> _pending = [];
  bool _sending = false;
  Timer? _sendTimer;
  int _failStreak = 0;
  File? _file;

  bool _disposed = false;

  // ---------------------------------------------------------------------
  // Status pemutaran -> durasi
  // ---------------------------------------------------------------------
  void _evaluate() {
    if (_disposed) return;
    final active = _engine.playing && _engine.state == EngineState.ready;
    final state = _engine.state;

    if (active) {
      final track = _getCurrentTrack();
      if (track == null) return;

      // Pindah lagu tanpa melewati state non-aktif (crossfade/gapless).
      if (_trackId != null && _trackId != track.id) {
        _finish('interrupted');
      }
      if (_trackId == null) _beginSession(track);

      _idleTimer?.cancel();
      if (!_running) {
        _sw
          ..reset()
          ..start();
        _running = true;
        _checkpointTimer?.cancel();
        _checkpointTimer =
            Timer.periodic(_checkpointEvery, (_) => _checkpoint());
      }
      return;
    }

    // Tidak aktif: hentikan penghitungan segera.
    _stopRunning();

    if (state == EngineState.idle || state == EngineState.error) {
      _finish('interrupted');
    } else if (state == EngineState.completed) {
      _finish('completed');
    } else if (_trackId != null) {
      // Pause / buffering / loading: sesi dibiarkan terbuka sebentar agar
      // jeda singkat tidak memecah sesi, lalu ditutup.
      _idleTimer?.cancel();
      _idleTimer = Timer(_idleFlushAfter, () => _finish('interrupted'));
    }
  }

  void _beginSession(Track track) {
    _sessionId = _uuidV4();
    _trackId = track.id;
    _trackTitle = track.title;
    _startedAt = DateTime.now().toUtc();
    _lastActiveAt = _startedAt;
    _accumMs = 0;
  }

  void _stopRunning() {
    if (!_running) return;
    _sw.stop();
    _accumMs += _sw.elapsedMilliseconds;
    _sw.reset();
    _running = false;
    _lastActiveAt = DateTime.now().toUtc();
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
  }

  /// Tutup sesi (jika ada) dan masukkan ke antrean kirim.
  void _finish(String status) {
    _stopRunning();
    _idleTimer?.cancel();
    _emit(status);
    _sessionId = null;
    _trackId = null;
    _trackTitle = null;
    _startedAt = null;
    _accumMs = 0;
  }

  /// Simpan progres tanpa menghentikan pemutaran (lindungi dari app dimatikan
  /// paksa). Sesi lanjutan memakai ID baru agar tidak terhitung ganda.
  void _checkpoint() {
    if (!_running || _trackId == null) return;
    final elapsed = _accumMs + _sw.elapsedMilliseconds;
    final now = DateTime.now().toUtc();
    final seconds = elapsed ~/ 1000;
    if (seconds < _minSessionSeconds) return;
    _enqueue(_buildPayload(seconds, now, 'interrupted'));
    // Sisa < 1 dtk dibawa ke sesi berikutnya, sehingga tidak ada yang hilang.
    _accumMs = elapsed % 1000;
    _sw
      ..reset()
      ..start();
    _sessionId = _uuidV4();
    _startedAt = now;
  }

  void _emit(String status) {
    if (_sessionId == null || _trackId == null) return;
    final seconds = _accumMs ~/ 1000;
    if (seconds < _minSessionSeconds) return;
    _enqueue(
        _buildPayload(seconds, _lastActiveAt ?? DateTime.now().toUtc(), status));
  }

  Map<String, dynamic> _buildPayload(
      int seconds, DateTime endedAt, String status) {
    var started = _startedAt ?? endedAt;
    // Rentang waktu minimal sepanjang durasi (server menolak durasi > rentang).
    final minStart = endedAt.subtract(Duration(seconds: seconds));
    if (started.isAfter(minStart)) started = minStart;
    return {
      'id': _sessionId,
      'track_id': _trackId,
      'track_title': _trackTitle,
      'started_at': started.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'duration_seconds': seconds,
      'status': status,
    };
  }

  // ---------------------------------------------------------------------
  // Antrean lokal + pengiriman
  // ---------------------------------------------------------------------
  void _enqueue(Map<String, dynamic> payload) {
    _pending.add(payload);
    while (_pending.length > _maxPending) {
      _pending.removeAt(0);
    }
    unawaited(_persist());
    _scheduleSend();
  }

  void _scheduleSend({Duration? delay}) {
    if (_disposed || _pending.isEmpty) return;
    _sendTimer?.cancel();
    final backoff = Duration(seconds: min(300, 2 << min(_failStreak, 7)));
    _sendTimer = Timer(delay ?? (_failStreak == 0 ? const Duration(seconds: 2) : backoff),
        () => unawaited(_sendAll()));
  }

  Future<void> _sendAll() async {
    if (_sending || _disposed || !StatsRepository.instance.available) return;
    _sending = true;
    try {
      final cutoff = DateTime.now().toUtc().subtract(_maxAge);
      _pending.removeWhere((p) {
        final end = DateTime.tryParse(p['ended_at'] as String? ?? '');
        return end == null || end.isBefore(cutoff);
      });

      while (_pending.isNotEmpty && !_disposed) {
        final item = _pending.first;
        final r = await StatsRepository.instance.recordSession(item);
        if (r == SessionSendResult.retry) {
          _failStreak++;
          break;
        }
        _failStreak = 0;
        _pending.remove(item); // done / rejected -> keluar dari antrean
        if (r == SessionSendResult.rejected) {
          log('Sesi ditolak server: ${item['id']}', name: 'ListeningTracker');
        }
      }
      await _persist();
    } finally {
      _sending = false;
    }
    if (_pending.isNotEmpty) _scheduleSend();
  }

  Future<File> _queueFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    return _file = File('${dir.path}${Platform.pathSeparator}listening_pending.json');
  }

  Future<void> _persist() async {
    try {
      final f = await _queueFile();
      await f.writeAsString(jsonEncode(_pending), flush: true);
    } catch (e) {
      log('Gagal menyimpan antrean: $e', name: 'ListeningTracker');
    }
  }

  Future<void> _loadPending() async {
    try {
      final f = await _queueFile();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is List) {
        for (final e in data) {
          if (e is Map) _pending.add(Map<String, dynamic>.from(e));
        }
      }
    } catch (e) {
      log('Gagal membaca antrean: $e', name: 'ListeningTracker');
    }
  }

  /// Kirim sekarang (mis. setelah profil/leaderboard dibuka) tanpa menunggu.
  Future<void> flushNow() async {
    if (_running) _checkpoint();
    await _sendAll();
  }

  // ---------------------------------------------------------------------
  // Lifecycle aplikasi: musik di background tetap dihitung; kita hanya
  // memastikan progres sudah tersimpan di disk.
  // ---------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _checkpoint();
      unawaited(_persist());
    } else if (state == AppLifecycleState.resumed) {
      _scheduleSend(delay: const Duration(seconds: 1));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopRunning();
    _emit('interrupted');
    _checkpointTimer?.cancel();
    _idleTimer?.cancel();
    _sendTimer?.cancel();
    await _stateSub?.cancel();
    await _playingSub?.cancel();
    await _completeSub?.cancel();
    await _connSub?.cancel();
    await _persist();
  }

  static final Random _rng = Random.secure();
  static String _uuidV4() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
