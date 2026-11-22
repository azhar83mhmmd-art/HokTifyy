import 'package:streambeats/core/config/app_config.dart';
import 'package:streambeats/services/db/dao/settings_dao.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Menentukan apakah layar login awal perlu ditampilkan.
/// Tampil sekali saat pertama dibuka (kecuali sudah login / sudah memilih
/// "Lanjutkan sebagai Tamu"). Dilewati jika Supabase belum dikonfigurasi.
class LoginGateService {
  LoginGateService._();

  static const String _key = 'loginGateDone';
  static bool _done = false;

  static Future<void> checkAndCacheDone(SettingsDAO settingsDao) async {
    _done = await settingsDao.getSettingBool(_key) ?? false;
  }

  static bool get shouldShow {
    if (!AppConfig.supabaseConfigured) return false;
    if (_done) return false;
    return Supabase.instance.client.auth.currentSession == null;
  }

  static Future<void> markDone(SettingsDAO settingsDao) async {
    await settingsDao.putSettingBool(_key, true);
    _done = true;
  }

  /// Dipanggil saat keluar akun: layar login akan muncul lagi di pembukaan
  /// berikutnya. TIDAK menyentuh data lokal (playlist, like, unduhan).
  static Future<void> reset(SettingsDAO settingsDao) async {
    await settingsDao.putSettingBool(_key, false);
    _done = false;
  }
}
