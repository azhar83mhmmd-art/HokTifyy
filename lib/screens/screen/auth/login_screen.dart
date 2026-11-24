import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:streambeats/core/config/app_config.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/services/db/dao/settings_dao.dart';
import 'package:streambeats/services/db/db_provider.dart';
import 'package:streambeats/services/login_gate_service.dart';
import 'package:streambeats/services/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

enum _AuthMode { login, signup, forgot }

/// Layar login awal Vynora Music: email + kata sandi, Google, atau tamu.
/// Responsif: satu kolom di HP, dua panel di tablet/desktop.
class LoginScreen extends StatelessWidget {
  final VoidCallback onComplete;

  const LoginScreen({super.key, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Default_Theme().defaultThemeData,
      home: _LoginBody(onComplete: onComplete),
    );
  }
}

class _LoginBody extends StatefulWidget {
  final VoidCallback onComplete;

  const _LoginBody({required this.onComplete});

  @override
  State<_LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<_LoginBody> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- logic

  void _setMode(_AuthMode m) {
    setState(() {
      _mode = m;
      _error = null;
      _info = null;
    });
  }

  Future<void> _finish() async {
    await LoginGateService.markDone(SettingsDAO(DBProvider.db));
    if (mounted) widget.onComplete();
  }

  String _friendly(Object e) {
    final raw = e is AuthException ? e.message : e.toString();
    final m = raw.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Email atau kata sandi salah.';
    }
    if (m.contains('email not confirmed')) {
      return 'Email belum dikonfirmasi. Cek kotak masuk (atau folder spam) kamu.';
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'Email ini sudah terdaftar. Silakan masuk.';
    }
    if (m.contains('at least') && m.contains('characters')) {
      return 'Kata sandi terlalu pendek (minimal 6 karakter).';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.';
    }
    if (m.contains('signups not allowed') || m.contains('signup is disabled')) {
      return 'Pendaftaran email dinonaktifkan di server.';
    }
    if (m.contains('socketexception') ||
        m.contains('clientexception') ||
        m.contains('failed host lookup') ||
        m.contains('connection')) {
      return 'Tidak ada koneksi internet. Periksa jaringan lalu coba lagi.';
    }
    return 'Terjadi kesalahan: $raw';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      switch (_mode) {
        case _AuthMode.login:
          final loginRes = await SupabaseAuthService.signInWithEmail(
              _emailCtrl.text, _passCtrl.text);
          if (loginRes.session != null) {
            await _finish();
            return;
          }
          setState(() => _error = 'Gagal masuk. Coba lagi.');
          break;
        case _AuthMode.signup:
          final signupRes = await SupabaseAuthService.signUpWithEmail(
              _emailCtrl.text, _passCtrl.text,
              name: _nameCtrl.text);
          if (signupRes.session != null) {
            await _finish();
            return;
          }
          // Konfirmasi email aktif di Supabase
          setState(() {
            _mode = _AuthMode.login;
            _passCtrl.clear();
            _confirmCtrl.clear();
            _info =
                'Akun dibuat. Kami mengirim email konfirmasi ke ${_emailCtrl.text.trim()}. Buka tautannya, lalu masuk.';
          });
          break;
        case _AuthMode.forgot:
          await SupabaseAuthService.sendPasswordReset(_emailCtrl.text);
          setState(() {
            _mode = _AuthMode.login;
            _info =
                'Jika email terdaftar, tautan reset kata sandi sudah dikirim. Cek kotak masuk kamu.';
          });
          break;
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    if (AppConfig.googleWebClientId.isEmpty) {
      setState(() {
        _info = null;
        _error =
            'Login Google belum dikonfigurasi (GOOGLE_WEB_CLIENT_ID kosong). Gunakan email atau lanjut sebagai tamu.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final googleRes = await SupabaseAuthService.signInWithGoogle();
      if (googleRes != null && googleRes.session != null) {
        await _finish();
        return;
      }
      // googleRes == null: dibatalkan pengguna
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Login Google gagal. Pastikan client Android (package & SHA-1) sudah benar.\n${_friendly(e)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    setState(() => _busy = true);
    await _finish();
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      body: Stack(
        children: [
          const _GlowBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 860;
                final form = _buildCard();
                if (wide) {
                  return Row(
                    children: [
                      const Expanded(child: _BrandPanel()),
                      Expanded(
                        child: _scrollCentered(c.maxHeight, form),
                      ),
                    ],
                  );
                }
                return _scrollCentered(
                  c.maxHeight,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(compact: c.maxHeight < 700),
                      SizedBox(height: c.maxHeight < 700 ? 16 : 28),
                      form,
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _scrollCentered(double minHeight, Widget child) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight > 48 ? minHeight - 48 : 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required bool compact}) {
    final size = compact ? 68.0 : 92.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.26),
            boxShadow: [
              BoxShadow(
                color: Default_Theme.accentColor1.withValues(alpha: 0.45),
                blurRadius: 36,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.26),
            child: Image.asset('assets/icons/hoktifyy_logo.png',
                fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (r) => Default_Theme.brandGradient.createShader(r),
          child: const Text(
            'Vynora Music',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Musik tanpa batas, dalam genggamanmu',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Default_Theme.primaryColor2.withValues(alpha: 0.9),
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    final isLogin = _mode == _AuthMode.login;
    final isSignup = _mode == _AuthMode.signup;
    final isForgot = _mode == _AuthMode.forgot;

    final title = isLogin
        ? 'Selamat datang kembali'
        : isSignup
            ? 'Buat akun baru'
            : 'Lupa kata sandi';
    final subtitle = isLogin
        ? 'Masuk untuk memakai playlist bersama dan sinkron antar perangkat.'
        : isSignup
            ? 'Daftar gratis, hanya butuh email.'
            : 'Masukkan email, kami kirim tautan untuk mengatur ulang.';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        decoration: BoxDecoration(
          color: Default_Theme.surfaceColor.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Default_Theme.outlineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Default_Theme.primaryColor2.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                if (_info != null) _Banner(text: _info!, isError: false),
                if (_error != null) _Banner(text: _error!, isError: true),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isSignup) ...[
                        _Field(
                          controller: _nameCtrl,
                          label: 'Nama (opsional)',
                          icon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Field(
                        controller: _emailCtrl,
                        label: 'Email',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction:
                            isForgot ? TextInputAction.done : TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Email wajib diisi';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                            return 'Format email tidak valid';
                          }
                          return null;
                        },
                        onSubmitted: isForgot ? (_) => _submit() : null,
                      ),
                      if (!isForgot) ...[
                        const SizedBox(height: 12),
                        _Field(
                          controller: _passCtrl,
                          label: 'Kata sandi',
                          icon: Icons.lock_outline_rounded,
                          obscure: _obscure,
                          textInputAction: isSignup
                              ? TextInputAction.next
                              : TextInputAction.done,
                          autofillHints: [
                            isSignup
                                ? AutofillHints.newPassword
                                : AutofillHints.password
                          ],
                          suffix: IconButton(
                            tooltip: _obscure ? 'Tampilkan' : 'Sembunyikan',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Default_Theme.primaryColor2,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          validator: (v) {
                            if ((v ?? '').isEmpty) return 'Kata sandi wajib diisi';
                            if (isSignup && v!.length < 6) {
                              return 'Minimal 6 karakter';
                            }
                            return null;
                          },
                          onSubmitted: isLogin ? (_) => _submit() : null,
                        ),
                      ],
                      if (isSignup) ...[
                        const SizedBox(height: 12),
                        _Field(
                          controller: _confirmCtrl,
                          label: 'Ulangi kata sandi',
                          icon: Icons.lock_reset_rounded,
                          obscure: _obscure,
                          textInputAction: TextInputAction.done,
                          validator: (v) => v != _passCtrl.text
                              ? 'Kata sandi tidak sama'
                              : null,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : () => _setMode(_AuthMode.forgot),
                      child: const Text('Lupa kata sandi?'),
                    ),
                  )
                else
                  const SizedBox(height: 10),
                const SizedBox(height: 4),
                _GradientButton(
                  label: isLogin
                      ? 'Masuk'
                      : isSignup
                          ? 'Daftar'
                          : 'Kirim tautan reset',
                  busy: _busy,
                  onPressed: _busy ? null : _submit,
                ),
                if (!isForgot) ...[
                  const SizedBox(height: 18),
                  const _OrDivider(),
                  const SizedBox(height: 18),
                  _GoogleButton(onPressed: _busy ? null : _google),
                ],
                const SizedBox(height: 12),
                _buildFooterLinks(),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Berbasis StreamBeats  •  Source oleh Valora Official  •  GPL v2+',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLinks() {
    final isLogin = _mode == _AuthMode.login;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              isLogin ? 'Belum punya akun?' : 'Sudah punya akun?',
              style: TextStyle(
                color: Default_Theme.primaryColor2.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _setMode(isLogin ? _AuthMode.signup : _AuthMode.login),
              child: Text(
                isLogin ? 'Daftar' : 'Masuk',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: _busy ? null : _guest,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('Lanjutkan sebagai Tamu'),
          style: TextButton.styleFrom(
            foregroundColor: Default_Theme.primaryColor2,
          ),
        ),
      ],
    );
  }
}

// ======================================================== sub-widgets

class _GlowBackground extends StatelessWidget {
  const _GlowBackground();

  @override
  Widget build(BuildContext context) {
    Widget orb(Color color, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: 0.38), color.withValues(alpha: 0)],
            ),
          ),
        );
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: -140, left: -120, child: orb(const Color(0xFF7C3AED), 440)),
          Positioned(bottom: -160, right: -140, child: orb(const Color(0xFFC026D3), 460)),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    Widget feature(IconData i, String t, String d) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Default_Theme.accentColor1.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(i, color: Default_Theme.accentColor1light, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(d,
                        style: TextStyle(
                            color: Default_Theme.primaryColor2
                                .withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset('assets/icons/hoktifyy_logo.png',
                    width: 110, height: 110, fit: BoxFit.cover),
              ),
              const SizedBox(height: 24),
              ShaderMask(
                shaderCallback: (r) => Default_Theme.brandGradient.createShader(r),
                child: const Text('Vynora Music',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              Text('Pemutar musik gratis tanpa iklan.',
                  style: TextStyle(
                      color: Default_Theme.primaryColor2, fontSize: 16)),
              const SizedBox(height: 36),
              feature(Icons.queue_music_rounded, 'Playlist bersama',
                  'Susun dan dengarkan playlist bareng teman lewat kode.'),
              feature(Icons.celebration_rounded, 'Party Room',
                  'Putar lagu yang sama secara sinkron di banyak perangkat.'),
              feature(Icons.cloud_done_rounded, 'Tersinkron',
                  'Akunmu tersimpan aman di cloud (Supabase).'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: Default_Theme.accentColor2,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Default_Theme.primaryColor2.withValues(alpha: 0.9),
            fontSize: 14),
        floatingLabelStyle: const TextStyle(color: Default_Theme.accentColor2),
        prefixIcon: Icon(icon, color: Default_Theme.primaryColor2, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Default_Theme.surfaceHighColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: border(Default_Theme.outlineColor),
        focusedBorder: border(Default_Theme.accentColor1, 1.6),
        errorBorder: border(const Color(0xFFEF4444)),
        focusedErrorBorder: border(const Color(0xFFEF4444), 1.6),
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: Default_Theme.brandGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Default_Theme.accentColor1.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(FontAwesome.google_brand,
            size: 20, color: const Color(0xFF4285F4)),
        label: const Text(
          'Lanjutkan dengan Google',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Default_Theme.surfaceHighColor,
          side: const BorderSide(color: Default_Theme.outlineColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(color: Default_Theme.outlineColor));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'atau',
            style: TextStyle(
              color: Default_Theme.primaryColor2.withValues(alpha: 0.8),
              fontSize: 12.5,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final bool isError;

  const _Banner({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12.8, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
