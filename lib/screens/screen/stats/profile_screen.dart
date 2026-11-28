import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/screens/widgets/snackbar.dart';
import 'package:streambeats/screens/widgets/stats/user_avatar.dart';
import 'package:streambeats/services/stats/stats_models.dart';
import 'package:streambeats/services/stats/stats_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Profil pengguna. [userId] == null -> profil sendiri (bisa diedit).
/// Profil orang lain mengikuti privasi yang dipilih pemiliknya (server-side).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final repo = StatsRepository.instance;
      if (!repo.available) throw StateError('not configured');
      await repo.ensureReady();
      final p = await repo.profile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _failed = p == null;
        _loading = false;
      });
      if (p != null && p.isSelf) repo.myProfile.value = p;
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit() async {
    final p = _profile;
    if (p == null) return;
    final updated = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _EditProfileSheet(profile: p),
    );
    if (updated != null && mounted) setState(() => _profile = updated);
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      backgroundColor: Default_Theme.themeColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(MingCute.arrow_left_line),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: const Text('Profile',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        actions: [
          if (p != null && p.isSelf)
            TextButton(onPressed: _edit, child: const Text('Edit')),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Default_Theme.accentColor2)))
          : (_failed || p == null)
              ? _Failed(onRetry: _load)
              : _ProfileBody(profile: p),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(MingCute.wifi_off_line, size: 34, color: Default_Theme.accentColor2),
          const SizedBox(height: 14),
          const Text('Couldn\'t load this profile',
              style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final accent = p.accentColor ?? Default_Theme.accentColor2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      children: [
        Center(
          child: UserAvatar(
            name: p.displayName,
            url: p.isLimited ? null : p.avatarUrl,
            accent: accent,
            frame: p.frame,
            size: 116,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(p.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Inter', color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        if (p.username != null) ...[
          const SizedBox(height: 4),
          Center(
            child: Text('@${p.username}',
                style: TextStyle(
                    fontFamily: 'Inter', color: accent.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
        if (p.bio != null && p.bio!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(p.bio!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.45)),
        ],
        const SizedBox(height: 28),
        if (p.isLimited)
          _Panel(
            child: Column(children: [
              Icon(MingCute.lock_line, color: accent, size: 26),
              const SizedBox(height: 10),
              const Text('This profile is private',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Only the owner can see listening stats here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
            ]),
          )
        else ...[
          _Panel(
            child: Column(children: [
              _StatLine(label: 'All time', seconds: p.totalAll, rank: p.rankAll, accent: accent),
              const _Hair(),
              _StatLine(label: 'This month', seconds: p.totalMonth, rank: p.rankMonth, accent: accent),
              const _Hair(),
              _StatLine(label: 'This week', seconds: p.totalWeek, rank: p.rankWeek, accent: accent),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _MiniStat(label: 'Listening sessions', value: '${p.sessions}')),
            const SizedBox(width: 12),
            Expanded(
                child: _MiniStat(
                    label: 'Member since',
                    value: p.memberSince == null ? '-' : _month(p.memberSince!))),
          ]),
        ],
      ],
    );
  }

  static String _month(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.year}';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Default_Theme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Default_Theme.outlineColor),
        ),
        child: child,
      );
}

class _Hair extends StatelessWidget {
  const _Hair();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 22, thickness: 1, color: Colors.white.withValues(alpha: 0.06));
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.seconds, required this.rank, required this.accent});
  final String label;
  final int seconds;
  final int? rank;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
        ),
        Text(seconds == 0 ? '-' : formatListening(seconds),
            style: const TextStyle(
                fontFamily: 'Inter', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        SizedBox(
          width: 46,
          child: Text(rank == null ? '' : '#$rank',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'Inter', color: accent, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ]);
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Inter', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        ]),
      );
}

// =====================================================================
// Edit profil
// =====================================================================
const _accentChoices = <String>[
  '#CFBCFF', '#8B5CF6', '#6FB7FF', '#5EC4A8', '#E58AB4', '#B8B8C8',
];
const _frames = <(String, String)>[
  ('none', 'None'),
  ('ring', 'Ring'),
  ('double', 'Double'),
  ('soft', 'Soft'),
];
const _maxAvatarBytes = 2 * 1024 * 1024;

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile});
  final UserProfile profile;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late String _frame;
  late bool _public;
  String? _accent; // '#RRGGBB' atau null
  Uint8List? _newAvatar;
  String? _newAvatarType;
  bool _removeAvatar = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.displayName);
    _username = TextEditingController(text: p.username ?? '');
    _bio = TextEditingController(text: p.bio ?? '');
    _frame = p.frame;
    _public = p.isPublic;
    _accent = p.accentColor == null ? null : colorToHex(p.accentColor!);
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// Deteksi format dari isi file (bukan hanya ekstensi).
  static String? _sniff(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length > 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  Future<void> _pickAvatar() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final f = res?.files.single;
      if (f == null) return;
      if (f.size > _maxAvatarBytes) {
        setState(() => _error = 'Photo is too large (max 2 MB).');
        return;
      }
      final bytes = f.bytes;
      final type = bytes == null ? null : _sniff(bytes);
      if (bytes == null || type == null) {
        setState(() => _error = 'Unsupported format. Use JPG, PNG or WebP.');
        return;
      }
      setState(() {
        _newAvatar = bytes;
        _newAvatarType = type;
        _removeAvatar = false;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Couldn\'t open the photo picker.');
    }
  }

  Future<void> _save() async {
    final p = widget.profile;
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    final bio = _bio.text.trim();

    if (name.isEmpty || name.length > 30) {
      setState(() => _error = 'Display name must be 1-30 characters.');
      return;
    }
    if (username.isNotEmpty && !RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(username)) {
      setState(() => _error = 'Username: 3-20 characters, a-z, 0-9, _ or .');
      return;
    }
    if (bio.length > 160) {
      setState(() => _error = 'Bio is limited to 160 characters.');
      return;
    }

    final patch = <String, dynamic>{};
    if (name != p.displayName) patch['display_name'] = name;
    if (username != (p.username ?? '')) patch['username'] = username;
    if (bio != (p.bio ?? '')) patch['bio'] = bio;
    final oldAccent = p.accentColor == null ? null : colorToHex(p.accentColor!);
    if (_accent != oldAccent) patch['accent_color'] = _accent ?? '';
    if (_frame != p.frame) patch['frame'] = _frame;
    if (_public != p.isPublic) patch['is_public'] = _public;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = StatsRepository.instance;
      if (_newAvatar != null) {
        patch['avatar_url'] = await repo.uploadAvatar(_newAvatar!, _newAvatarType!);
      } else if (_removeAvatar) {
        patch['avatar_url'] = '';
      }
      final updated = patch.isEmpty ? p : (await repo.updateProfile(patch)) ?? p;
      HapticFeedback.lightImpact();
      if (!mounted) return;
      SnackbarService.showMessage('Profile updated');
      Navigator.of(context).pop(updated);
    } on PostgrestException catch (e) {
      setState(() {
        _saving = false;
        _error = e.code == '23505' ? 'That username is already taken.' : e.message;
      });
    } on StorageException catch (e) {
      setState(() {
        _saving = false;
        _error = 'Photo upload failed: ${e.message}';
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'Couldn\'t save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final accent = parseHexColor(_accent) ?? Default_Theme.accentColor2;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        decoration: const BoxDecoration(
          color: Default_Theme.surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Edit profile',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            Center(
              child: GestureDetector(
                onTap: _saving ? null : _pickAvatar,
                child: Stack(children: [
                  _newAvatar != null
                      ? SizedBox(
                          width: 96,
                          height: 96,
                          child: ClipOval(child: Image.memory(_newAvatar!, fit: BoxFit.cover, cacheWidth: 288)),
                        )
                      : UserAvatar(
                          name: _name.text,
                          url: _removeAvatar ? null : p.avatarUrl,
                          accent: accent,
                          frame: _frame,
                          size: 96,
                        ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Default_Theme.primaryContainerColor,
                        border: Border.all(color: Default_Theme.surfaceColor, width: 3),
                      ),
                      child: const Icon(MingCute.camera_line, size: 16, color: Default_Theme.onPrimaryContainerColor),
                    ),
                  ),
                ]),
              ),
            ),
            if (_newAvatar != null || (p.avatarUrl != null && !_removeAvatar))
              Center(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _newAvatar = null;
                            _newAvatarType = null;
                            _removeAvatar = p.avatarUrl != null;
                          }),
                  child: const Text('Remove photo'),
                ),
              ),
            const SizedBox(height: 8),
            _Field(controller: _name, label: 'Display name', maxLength: 30, onChanged: (_) => setState(() {})),
            const SizedBox(height: 14),
            _Field(
              controller: _username,
              label: 'Username',
              prefix: '@',
              maxLength: 20,
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]'))],
            ),
            const SizedBox(height: 14),
            _Field(controller: _bio, label: 'Bio', maxLength: 160, maxLines: 3),
            const SizedBox(height: 18),
            const _Caption('Accent color'),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final hex in _accentChoices)
                _Swatch(
                  color: parseHexColor(hex)!,
                  selected: _accent?.toUpperCase() == hex,
                  onTap: () => setState(() => _accent = hex),
                ),
              _Swatch(color: null, selected: _accent == null, onTap: () => setState(() => _accent = null)),
            ]),
            const SizedBox(height: 20),
            const _Caption('Photo frame'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final f in _frames)
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _frame == f.$1,
                  onSelected: (_) => setState(() => _frame = f.$1),
                ),
            ]),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _public,
              onChanged: (v) => setState(() => _public = v),
              title: const Text('Public profile',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('When off, others only see your name on the leaderboard.',
                  style: TextStyle(fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13)),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: Colors.white.withValues(alpha: 0.42)));
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.prefix,
    this.maxLength,
    this.maxLines = 1,
    this.formatters,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final int? maxLength;
  final int maxLines;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        inputFormatters: formatters,
        onChanged: onChanged,
        style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
          filled: true,
          fillColor: Default_Theme.surfaceHighColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color? color; // null = default aplikasi
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: color == null ? 'Default accent' : 'Accent color',
          child: Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? Default_Theme.surfaceHighColor,
                border: color == null ? Border.all(color: Colors.white.withValues(alpha: 0.3)) : null,
              ),
              child: color == null
                  ? Icon(MingCute.close_line, size: 14, color: Colors.white.withValues(alpha: 0.6))
                  : null,
            ),
          ),
        ),
      );
}
