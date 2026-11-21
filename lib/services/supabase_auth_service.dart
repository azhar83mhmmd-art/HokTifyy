import 'package:google_sign_in/google_sign_in.dart';
import 'package:streambeats/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const webClientId = AppConfig.googleWebClientId;

  static bool _isInitialized = false;

  static Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await GoogleSignIn.instance.initialize(
          serverClientId: webClientId.isEmpty ? null : webClientId);
      _isInitialized = true;
    }
  }

  static Future<AuthResponse?> signInWithGoogle() async {
    try {
      await _ensureInitialized();
      final googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        return null; // User canceled the login
      }
      
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'No ID Token found.';
      }

      return await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } catch (e) {
      print('Google Sign-In Error: $e');
      rethrow;
    }
  }

  /// Masuk dengan email + kata sandi.
  static Future<AuthResponse> signInWithEmail(String email, String password) {
    return _supabase.auth
        .signInWithPassword(email: email.trim(), password: password);
  }

  /// Daftar dengan email + kata sandi. `session` pada hasilnya bernilai null
  /// jika Supabase mewajibkan konfirmasi email.
  static Future<AuthResponse> signUpWithEmail(String email, String password,
      {String? name}) {
    final n = name?.trim() ?? '';
    return _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: n.isEmpty ? null : {'full_name': n},
    );
  }

  /// Kirim tautan reset kata sandi ke email.
  static Future<void> sendPasswordReset(String email) {
    return _supabase.auth.resetPasswordForEmail(email.trim());
  }

  /// Pastikan ada sesi Supabase. Jika belum login, otomatis masuk sebagai
  /// pengguna anonim supaya Playlist Bersama / Party langsung bisa dipakai.
  /// (Butuh "Allow anonymous sign-ins" aktif di Supabase. Login Google tetap
  /// tersedia di Pengaturan untuk akun permanen.)
  static Future<User> ensureSignedIn() async {
    final existing = _supabase.auth.currentUser;
    if (existing != null) return existing;
    if (!AppConfig.supabaseConfigured) {
      throw Exception(
          'Supabase belum dikonfigurasi (SUPABASE_URL / SUPABASE_ANON_KEY).');
    }
    try {
      final res = await _supabase.auth.signInAnonymously();
      final user = res.user ?? _supabase.auth.currentUser;
      if (user == null) throw Exception('Login anonim gagal.');
      return user;
    } on AuthException catch (e) {
      throw Exception(
          'Login otomatis gagal: ${e.message}. Aktifkan "Allow anonymous sign-ins" di Supabase (Authentication > Sign In / Providers) atau login Google di Pengaturan.');
    }
  }

  static Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
      await _supabase.auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
    }
  }

  static User? get currentUser => _supabase.auth.currentUser;
  
  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}