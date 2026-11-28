import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:streambeats/core/theme/app_theme.dart';

/// Foto profil bulat + dekorasi (frame) pilihan pengguna.
/// frame: none | ring | double | soft  (warna mengikuti aksen profil,
/// emas/silver/bronze sengaja TIDAK dipakai di sini - khusus podium).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 44,
    this.accent,
    this.frame = 'none',
    this.borderColor,
    this.borderWidth = 0,
  });

  final String name;
  final String? url;
  final double size;
  final Color? accent;
  final String frame;

  /// Cincin tambahan dari luar (mis. warna podium).
  final Color? borderColor;
  final double borderWidth;

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => String.fromCharCode(e.runes.first).toUpperCase());
    final s = parts.join();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Default_Theme.accentColor2;
    final ringGap = switch (frame) {
      'double' => 6.0,
      'ring' => 3.5,
      'soft' => 5.0,
      _ => 0.0,
    };
    final inner = size - ringGap * 2 - borderWidth * 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = (inner * dpr).round().clamp(32, 512);

    final photo = ClipOval(
      child: SizedBox(
        width: inner,
        height: inner,
        child: (url != null && url!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: cache,
                memCacheHeight: cache,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => _Initials(name: name, size: inner, accent: a),
                errorWidget: (_, __, ___) => _Initials(name: name, size: inner, accent: a),
              )
            : _Initials(name: name, size: inner, accent: a),
      ),
    );

    Widget framed = photo;
    if (frame != 'none') {
      framed = Container(
        width: size - borderWidth * 2,
        height: size - borderWidth * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: a.withValues(alpha: frame == 'soft' ? 0.35 : 0.9),
            width: frame == 'soft' ? 3 : 1.6,
          ),
        ),
        child: frame == 'double'
            ? Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: a.withValues(alpha: 0.35), width: 1),
                ),
                child: photo,
              )
            : photo,
      );
    }

    if (borderWidth > 0 && borderColor != null) {
      framed = Container(
        padding: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor!, width: borderWidth),
        ),
        child: framed,
      );
    }
    return SizedBox(width: size, height: size, child: Center(child: framed));
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size, required this.accent});
  final String name;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: Color.alphaBlend(accent.withValues(alpha: 0.22), Default_Theme.surfaceHighColor),
      child: Text(
        UserAvatar.initialsOf(name),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
