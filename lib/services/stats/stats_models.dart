import 'package:flutter/painting.dart';

/// Periode leaderboard. Nilai [apiValue] dipakai langsung oleh RPC Supabase.
enum StatsPeriod {
  all('all', 'All Time'),
  month('month', 'Monthly'),
  week('week', 'Weekly');

  const StatsPeriod(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// Satu baris leaderboard (hasil RPC get_leaderboard / get_my_rank).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.totalSeconds,
    this.username,
    this.avatarUrl,
    this.accentColor,
    this.frame = 'none',
    this.isPublic = true,
    this.prevRank,
  });

  final int rank;
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final Color? accentColor;
  final String frame;
  final bool isPublic;
  final int totalSeconds;

  /// Peringkat pada snapshot pembanding di server (null = belum ada data).
  final int? prevRank;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: (j['rank'] as num).toInt(),
        userId: j['user_id'] as String,
        displayName: (j['display_name'] as String?)?.trim().isNotEmpty == true
            ? (j['display_name'] as String).trim()
            : 'Listener',
        username: j['username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        accentColor: parseHexColor(j['accent_color'] as String?),
        frame: (j['frame'] as String?) ?? 'none',
        isPublic: (j['is_public'] as bool?) ?? true,
        totalSeconds: (j['total_seconds'] as num).toInt(),
        prevRank: (j['prev_rank'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is LeaderboardEntry &&
      other.rank == rank &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.accentColor == accentColor &&
      other.frame == frame &&
      other.prevRank == prevRank &&
      other.totalSeconds == totalSeconds;

  @override
  int get hashCode => Object.hash(rank, userId, displayName, avatarUrl,
      accentColor, frame, totalSeconds, prevRank);
}

/// Profil pengguna (hasil RPC get_user_profile / update_my_profile).
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.isSelf,
    this.username,
    this.bio,
    this.avatarUrl,
    this.accentColor,
    this.frame = 'none',
    this.isPublic = true,
    this.totalAll = 0,
    this.totalMonth = 0,
    this.totalWeek = 0,
    this.rankAll,
    this.rankMonth,
    this.rankWeek,
    this.sessions = 0,
    this.memberSince,
  });

  final String userId;
  final String displayName;
  final bool isSelf;
  final String? username;
  final String? bio;
  final String? avatarUrl;
  final Color? accentColor;
  final String frame;
  final bool isPublic;
  final int totalAll;
  final int totalMonth;
  final int totalWeek;
  final int? rankAll;
  final int? rankMonth;
  final int? rankWeek;
  final int sessions;
  final DateTime? memberSince;

  /// Profil privat milik orang lain: hanya nama + aksen yang dikirim server.
  bool get isLimited => !isSelf && !isPublic;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: j['user_id'] as String,
        displayName: (j['display_name'] as String?) ?? 'Listener',
        isSelf: (j['is_self'] as bool?) ?? false,
        username: j['username'] as String?,
        bio: j['bio'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        accentColor: parseHexColor(j['accent_color'] as String?),
        frame: (j['frame'] as String?) ?? 'none',
        isPublic: (j['is_public'] as bool?) ?? true,
        totalAll: (j['total_all'] as num?)?.toInt() ?? 0,
        totalMonth: (j['total_month'] as num?)?.toInt() ?? 0,
        totalWeek: (j['total_week'] as num?)?.toInt() ?? 0,
        rankAll: (j['rank_all'] as num?)?.toInt(),
        rankMonth: (j['rank_month'] as num?)?.toInt(),
        rankWeek: (j['rank_week'] as num?)?.toInt(),
        sessions: (j['sessions'] as num?)?.toInt() ?? 0,
        memberSince: j['member_since'] == null
            ? null
            : DateTime.tryParse(j['member_since'] as String)?.toLocal(),
      );
}

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(hex.trim());
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

String colorToHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// "92 jam" / "3 j 25 m" / "12 m" / "45 d" - ringkas untuk baris leaderboard.
String formatListening(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '${m}m';
  if (h >= 100) return '${h}h';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
