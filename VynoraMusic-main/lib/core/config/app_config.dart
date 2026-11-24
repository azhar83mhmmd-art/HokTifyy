// Vynora Music - runtime configuration.
//
// Semua nilai di sini dikirim saat build lewat --dart-define
// (GitHub Actions membacanya dari GitHub Secrets), jadi tidak ada
// key / URL yang di-hardcode di source code.
//
//   flutter build apk --release \
//     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=eyJ... \
//     --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com \
//     --dart-define=HOKTIFYY_REPO=usernameGithub/HokTifyy

class AppConfig {
  AppConfig._();

  static const String appName = 'Vynora Music';

  /// Project URL dari Supabase: Settings -> API -> Project URL
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  /// Supabase "anon public" key (aman dipakai di client, dilindungi RLS).
  /// JANGAN pernah memakai service_role key di sini.
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// OAuth "Web client ID" dari Google Cloud (untuk Login Google via Supabase).
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

  /// Repo GitHub tempat APK dirilis, format `user/repo`.
  /// Dipakai untuk cek update. Kosong = cek update dimatikan.
  static const String githubRepo =
      String.fromEnvironment('HOKTIFYY_REPO', defaultValue: '');

  static const bool supabaseConfigured =
      supabaseUrl != '' && supabaseAnonKey != '';

  static const bool updatesEnabled = githubRepo != '';

  /// Halaman proyek (dipakai tombol "buka web" / share).
  static const String websiteUrl =
      githubRepo != '' ? 'https://github.com/$githubRepo' : 'https://github.com/';

  // Placeholder agar Supabase.initialize() tidak crash saat belum dikonfigurasi.
  // Fitur cloud (login, playlist bersama, party) akan gagal dengan pesan error
  // jaringan biasa, sedangkan pemutar musik lokal tetap berjalan normal.
  static const String placeholderSupabaseUrl = 'https://not-configured.invalid';
  static const String placeholderAnonKey = 'not-configured';
}
