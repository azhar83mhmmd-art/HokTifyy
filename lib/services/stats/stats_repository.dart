import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:streambeats/core/config/app_config.dart';
import 'package:streambeats/services/stats/stats_models.dart';
import 'package:streambeats/services/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hasil pengiriman satu sesi ke server.
enum SessionSendResult {
  /// Diterima atau sudah pernah diterima: aman dihapus dari antrean lokal.
  done,

  /// Ditolak permanen oleh validasi server: jangan dikirim ulang.
  rejected,

  /// Gagal sementara (jaringan/auth): simpan, coba lagi nanti.
  retry,
}

/// Semua akses data Stats & Profil ke Supabase. Seluruh perhitungan,
/// validasi, dan ranking ada di RPC server-side (supabase/stats_leaderboard.sql).
class StatsRepository {
  StatsRepository._();
  static final StatsRepository instance = StatsRepository._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Profil pengguna yang sedang login. Dipakai avatar di seluruh aplikasi
  /// (Home, drawer, Stats) sehingga perubahan profil langsung tampil di sana.
  final ValueNotifier<UserProfile?> myProfile = ValueNotifier<UserProfile?>(null);
  bool _warming = false;

  /// Muat profil sendiri bila sudah login (tidak memicu login anonim).
  Future<void> warmProfile() async {
    final uid = currentUserId;
    if (uid == null || _warming) return;
    if (myProfile.value?.userId == uid) return;
    _warming = true;
    try {
      await _db.rpc('ensure_my_profile');
      final p = await profile();
      if (p != null && p.isSelf) myProfile.value = p;
    } catch (_) {
    } finally {
      _warming = false;
    }
  }

  /// Dipanggil saat logout / pergantian akun.
  void clearProfile() => myProfile.value = null;

  bool get available => AppConfig.supabaseConfigured;
  String? get currentUserId => available ? _db.auth.currentUser?.id : null;

  /// Pastikan ada sesi (login anonim otomatis jika belum login), lalu
  /// pastikan baris profil ada.
  Future<String> ensureReady() async {
    final user = await SupabaseAuthService.ensureSignedIn();
    try {
      await _db.rpc('ensure_my_profile');
    } catch (_) {}
    return user.id;
  }

  Future<List<LeaderboardEntry>> leaderboard(StatsPeriod period,
      {int limit = 50, int offset = 0}) async {
    final rows = await _db.rpc('get_leaderboard', params: {
      'p_period': period.apiValue,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List)
        .map((e) => LeaderboardEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Minta server membuat snapshot peringkat harian (idempoten, maks 1x/24 jam).
  /// Dipakai untuk indikator naik/turun yang tersimpan di server.
  Future<void> touchRankSnapshot(StatsPeriod period) async {
    try {
      await _db.rpc('touch_rank_snapshot', params: {'p_period': period.apiValue});
    } catch (_) {}
  }

  Future<LeaderboardEntry?> myRank(StatsPeriod period) async {
    final rows =
        await _db.rpc('get_my_rank', params: {'p_period': period.apiValue});
    final list = rows as List;
    if (list.isEmpty) return null;
    return LeaderboardEntry.fromJson(Map<String, dynamic>.from(list.first));
  }

  Future<UserProfile?> profile([String? userId]) async {
    final res = await _db.rpc('get_user_profile', params: {'p_user_id': userId});
    if (res == null) return null;
    return UserProfile.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// [patch] hanya berisi kunci yang diubah (lihat update_my_profile).
  Future<UserProfile?> updateProfile(Map<String, dynamic> patch) async {
    final res = await _db.rpc('update_my_profile', params: {'p_patch': patch});
    if (res == null) return null;
    final p = UserProfile.fromJson(Map<String, dynamic>.from(res as Map));
    myProfile.value = p; // sinkron ke seluruh aplikasi
    return p;
  }

  /// Unggah foto ke bucket `avatars/<uid>/...`, kembalikan URL publik.
  Future<String> uploadAvatar(Uint8List bytes, String contentType) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Belum login.');
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    // Nama unik per unggahan -> URL baru, cache gambar tidak menampilkan foto lama.
    final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _db.storage.from('avatars').getPublicUrl(path);
  }

  /// Kirim satu sesi mendengarkan. Tidak pernah melempar exception.
  Future<SessionSendResult> recordSession(Map<String, dynamic> s) async {
    if (!available || _db.auth.currentUser == null) {
      return SessionSendResult.retry;
    }
    try {
      final res = await _db.rpc('record_listening_session', params: {
        'p_session_id': s['id'],
        'p_track_id': s['track_id'],
        'p_track_title': s['track_title'],
        'p_started_at': s['started_at'],
        'p_ended_at': s['ended_at'],
        'p_duration_seconds': s['duration_seconds'],
        'p_status': s['status'],
      });
      final accepted = (res is Map && res['accepted'] == true);
      if (accepted) return SessionSendResult.done;
      final reason = res is Map ? res['reason'] as String? : null;
      return reason == 'duplicate'
          ? SessionSendResult.done
          : SessionSendResult.rejected;
    } catch (_) {
      // Jaringan putus / belum login / error server sementara: simpan & coba lagi.
      return SessionSendResult.retry;
    }
  }

  /// Sinyal realtime: ada perubahan total pada periode mana pun.
  RealtimeChannel subscribeTotals(void Function() onChange) {
    final ch = _db.channel('stats_totals_${DateTime.now().microsecondsSinceEpoch}');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'listening_totals',
          callback: (_) => onChange(),
        )
        .subscribe();
    return ch;
  }

  Future<void> unsubscribe(RealtimeChannel ch) async {
    try {
      await _db.removeChannel(ch);
    } catch (_) {}
  }
}
