import 'package:streambeats/core/models/exported.dart';
import 'dart:async';
import 'dart:developer';

import 'package:streambeats/services/db/dao/playlist_dao.dart';
import 'package:streambeats/services/db/dao/track_dao.dart';
import 'package:streambeats/services/db/db_provider.dart';
import 'package:streambeats/services/db/global_db.dart';
import 'package:streambeats/services/import_export_service.dart';
import 'package:streambeats/core/config/app_config.dart';
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cadangan otomatis library (lagu disukai + playlist buatan/impor) ke
/// Supabase, per akun. Tujuannya: data tidak hilang walau aplikasi
/// di-uninstall / data dihapus, lalu login lagi.
///
/// - Hanya untuk akun permanen (email / Google); tamu/anonim tidak disinkron.
/// - Saat login: data cloud DIGABUNG ke data lokal (tidak menimpa/menghapus).
/// - Setelah itu setiap perubahan dikirim (debounce 4 detik).
/// - File unduhan offline tetap berada di perangkat (tidak ikut cloud).
class LibrarySyncService {
  LibrarySyncService._();

  static bool _started = false;
  static Timer? _debounce;
  static bool _restoring = false;
  static StreamSubscription? _authSub;

  static SupabaseClient get _sb => Supabase.instance.client;

  static User? get _user {
    final u = _sb.auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u;
  }

  static PlaylistDAO get _dao =>
      PlaylistDAO(DBProvider.db, TrackDAO(DBProvider.db));

  static void start() {
    if (_started || !AppConfig.supabaseConfigured) return;
    _started = true;

    _authSub = _sb.auth.onAuthStateChange.listen((state) {
      if ((state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.initialSession) &&
          _user != null) {
        unawaited(restoreAndPush());
      }
    });

    unawaited(() async {
      final isar = await DBProvider.db;
      isar.playlistEntryDBs.watchLazy().listen((_) => _schedulePush());
      isar.playlistDBs.watchLazy().listen((_) => _schedulePush());
    }());

    if (_user != null) unawaited(restoreAndPush());
  }

  static void _schedulePush() {
    if (_restoring || _user == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), pushNow);
  }

  static bool _syncable(PlaylistDB p) =>
      p.name == DBProvider.likedPlaylist ||
      !DBProvider.standardPlaylists.contains(p.name);

  static Future<Map<String, dynamic>> _snapshot() async {
    final all = await _dao.getAllPlaylists();
    final out = <Map<String, dynamic>>[];
    for (final p in all.where(_syncable)) {
      final tracks = await _dao.getPlaylistTracks(p.id);
      out.add({
        'name': p.name,
        'tracks': tracks.map(ImportExportService.trackToMap).toList(),
      });
    }
    return {'version': 1, 'playlists': out};
  }

  /// Kirim keadaan lokal ke cloud.
  static Future<void> pushNow() async {
    final user = _user;
    if (user == null || _restoring) return;
    try {
      _debounce?.cancel();
      final snap = await _snapshot();
      await _sb.from('user_library').upsert({
        'user_id': user.id,
        'data': snap,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      log('Library push gagal', error: e, name: 'LibrarySync');
    }
  }

  /// Gabungkan data cloud ke lokal, lalu kirim hasil gabungan.
  static Future<void> restoreAndPush() async {
    final user = _user;
    if (user == null) return;
    _restoring = true;
    try {
      final row = await _sb
          .from('user_library')
          .select('data')
          .eq('user_id', user.id)
          .maybeSingle();
      final data = row?['data'];
      if (data is Map && data['playlists'] is List) {
        for (final item in (data['playlists'] as List)) {
          if (item is! Map) continue;
          final name = (item['name'] ?? '').toString();
          if (name.isEmpty) continue;
          final id = await _dao.ensurePlaylist(name);
          final tracks = <Track>[];
          for (final t in (item['tracks'] as List? ?? const [])) {
            if (t is Map) {
              try {
                tracks.add(ImportExportService.trackFromMap(
                    Map<String, dynamic>.from(t)));
              } catch (_) {}
            }
          }
          await _dao.addTracksToPlaylist(id, tracks);
        }
      }
    } catch (e) {
      log('Library restore gagal', error: e, name: 'LibrarySync');
    } finally {
      _restoring = false;
    }
    await pushNow();
  }

  static Future<void> dispose() async {
    await _authSub?.cancel();
    _debounce?.cancel();
    _started = false;
  }
}
