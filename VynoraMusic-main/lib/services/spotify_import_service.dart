import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;
import 'package:streambeats/src/rust/api/plugin/models.dart';

/// Hasil pembacaan playlist Spotify (belum dicocokkan ke lagu pemutar).
class SpotifyImportResult {
  final String? name;
  final String? thumbnailUrl;
  final List<ImportTrackItem> tracks;

  const SpotifyImportResult({
    required this.tracks,
    this.name,
    this.thumbnailUrl,
  });
}

class SpotifyImportException implements Exception {
  final String message;
  const SpotifyImportException(this.message);

  @override
  String toString() => message;
}

/// Membaca daftar lagu dari Spotify TANPA API resmi:
///  1. link playlist publik (halaman embed, best-effort, maks. sekitar 100 lagu)
///  2. teks "Artis - Judul" per baris
///  3. CSV hasil ekspor (mis. Exportify)
/// Pencocokan ke lagu yang bisa diputar dikerjakan oleh ContentImportCubit.
class SpotifyImportService {
  static final RegExp _idRe = RegExp(r'playlist[/:]([A-Za-z0-9]{22})');

  static bool looksLikeLink(String input) =>
      input.toLowerCase().contains('spotify') && _idRe.hasMatch(input);

  /// Otomatis memilih: link atau teks.
  static Future<SpotifyImportResult> fromInput(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const SpotifyImportException('Masukan masih kosong.');
    }
    if (looksLikeLink(input)) return fromLink(input);
    return fromText(input);
  }


  // ------------------------------------------------------ rapikan judul

  /// Membuang bagian judul yang tidak menentukan lagunya (supaya pencarian
  /// lebih tepat), tetapi mempertahankan penanda versi penting seperti
  /// live, remix, acoustic, instrumental, sped up.
  static String cleanTitle(String raw) {
    var s = raw.trim();
    // "(feat. X)" / "[with X]" -> artis tamu sudah ada di daftar artis.
    s = s.replaceAll(
      RegExp(r'\s*[\(\[]\s*(?:feat|ft|featuring|with)\b[^\)\]]*[\)\]]',
          caseSensitive: false),
      '',
    );
    // Sufiks non-semantik setelah " - ".
    s = s.replaceFirst(
      RegExp(
        r'\s+-\s+(?:\d{4}\s+)?(?:digital\s+)?remaster(?:ed)?(?:\s+\d{4})?(?:\s+version)?\s*$'
        r'|\s+-\s+(?:mono|stereo)(?:\s+version)?\s*$'
        r'|\s+-\s+(?:single|album)\s+version\s*$'
        r'|\s+-\s+from\s+["“”].*$'
        r'|\s+-\s+bonus\s+track\s*$',
        caseSensitive: false,
      ),
      '',
    );
    s = s.trim();
    return s.isEmpty ? raw.trim() : s;
  }

  // ------------------------------------------------------------- link

  static Future<SpotifyImportResult> fromLink(String link) async {
    final id = _idRe.firstMatch(link)?.group(1);
    if (id == null) {
      throw const SpotifyImportException('Tautan playlist Spotify tidak valid.');
    }

    final http.Response res;
    try {
      res = await http.get(
        Uri.parse('https://open.spotify.com/embed/playlist/$id'),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      log('Spotify embed request failed: $e', name: 'SpotifyImport');
      throw const SpotifyImportException(
          'Tidak bisa terhubung ke Spotify. Periksa internet lalu coba lagi.');
    }

    if (res.statusCode != 200) {
      throw SpotifyImportException(
          'Playlist tidak bisa dibuka (kode ${res.statusCode}). Pastikan playlist bersifat publik, atau tempel daftar lagu sebagai teks.');
    }

    final m = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(res.body);
    if (m == null) {
      throw const SpotifyImportException(
          'Format halaman Spotify berubah. Gunakan import teks atau CSV.');
    }

    dynamic data;
    try {
      data = jsonDecode(m.group(1)!);
    } catch (_) {
      throw const SpotifyImportException(
          'Data playlist tidak terbaca. Gunakan import teks atau CSV.');
    }

    final list = _findKey(data, 'trackList');
    if (list is! List || list.isEmpty) {
      throw const SpotifyImportException(
          'Daftar lagu tidak ditemukan (playlist kosong atau privat). Gunakan import teks atau CSV.');
    }

    final tracks = <ImportTrackItem>[];
    for (final t in list) {
      if (t is! Map) continue;
      final title = cleanTitle((t['title'] ?? '').toString());
      if (title.isEmpty) continue;
      final subtitle = (t['subtitle'] ?? '').toString();
      final artists = subtitle
          .split(RegExp(r',\s*|\u00a0|;\s*'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final dur = t['duration'];
      final uri = (t['uri'] ?? '').toString();
      tracks.add(ImportTrackItem(
        title: title,
        artists: artists,
        durationMs: dur is num ? BigInt.from(dur.toInt()) : null,
        isExplicit: t['isExplicit'] == true,
        sourceId: uri.startsWith('spotify:track:')
            ? uri.substring('spotify:track:'.length)
            : null,
      ));
    }
    if (tracks.isEmpty) {
      throw const SpotifyImportException('Tidak ada lagu yang bisa dibaca.');
    }

    final entity = _findKey(data, 'entity');
    String? name;
    String? cover;
    if (entity is Map) {
      name = (entity['name'] ?? entity['title'])?.toString();
      final art = entity['coverArt'];
      if (art is Map && art['sources'] is List && (art['sources'] as List).isNotEmpty) {
        final first = (art['sources'] as List).first;
        if (first is Map) cover = first['url']?.toString();
      }
    }

    return SpotifyImportResult(name: name, thumbnailUrl: cover, tracks: tracks);
  }

  static dynamic _findKey(dynamic node, String key, [int depth = 0]) {
    if (depth > 12) return null;
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final r = _findKey(v, key, depth + 1);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findKey(v, key, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  // ------------------------------------------------------------- teks

  /// Satu lagu per baris. Format yang dikenali: "Artis - Judul" atau "Judul".
  static SpotifyImportResult fromText(String raw) {
    final tracks = <ImportTrackItem>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      var l = line.trim();
      if (l.isEmpty) continue;
      l = l.replaceFirst(RegExp(r'^\d+[\.\)]\s+'), ''); // buang nomor urut
      final parts = l.split(RegExp(r'\s+[-–—]\s+'));
      if (parts.length >= 2) {
        final artists = parts.first
            .split(RegExp(r',\s*|;\s*'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        tracks.add(ImportTrackItem(
          title: cleanTitle(parts.sublist(1).join(' - ')),
          artists: artists,
          isExplicit: false,
        ));
      } else {
        tracks.add(ImportTrackItem(
            title: cleanTitle(l), artists: const [], isExplicit: false));
      }
    }
    if (tracks.isEmpty) {
      throw const SpotifyImportException('Tidak ada lagu yang bisa dibaca.');
    }
    return SpotifyImportResult(tracks: tracks);
  }

  // -------------------------------------------------------------- CSV

  /// CSV hasil ekspor (kolom "Track Name", "Artist Name(s)", "Album Name",
  /// "Duration (ms)"), mis. dari Exportify.
  static SpotifyImportResult fromCsv(String content, {String? name}) {
    final rows = _parseCsv(content.replaceFirst('\uFEFF', ''));
    if (rows.length < 2) {
      throw const SpotifyImportException('File CSV kosong.');
    }
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int col(bool Function(String) test) => header.indexWhere(test);

    final iTitle = col((h) => h == 'track name' || h == 'title' || h == 'name');
    final iArtist = col((h) => h.startsWith('artist'));
    final iAlbum = col((h) => h.startsWith('album name') || h == 'album');
    final iDur = col((h) => h.contains('duration'));
    final iUri = col((h) => h == 'track uri' || h == 'spotify uri' || h == 'spotify id');
    if (iTitle < 0) {
      throw const SpotifyImportException(
          'Kolom "Track Name" tidak ditemukan di file CSV.');
    }

    String cell(List<String> r, int i) =>
        (i >= 0 && i < r.length) ? r[i].trim() : '';

    final tracks = <ImportTrackItem>[];
    for (final r in rows.skip(1)) {
      final title = cleanTitle(cell(r, iTitle));
      if (title.isEmpty) continue;
      final artists = cell(r, iArtist)
          .split(RegExp(r';|,'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final dur = int.tryParse(cell(r, iDur));
      final uri = cell(r, iUri);
      tracks.add(ImportTrackItem(
        title: title,
        artists: artists,
        albumTitle: cell(r, iAlbum).isEmpty ? null : cell(r, iAlbum),
        durationMs: dur != null ? BigInt.from(dur) : null,
        isExplicit: false,
        sourceId: uri.startsWith('spotify:track:')
            ? uri.substring('spotify:track:'.length)
            : null,
      ));
    }
    if (tracks.isEmpty) {
      throw const SpotifyImportException('Tidak ada lagu yang bisa dibaca.');
    }
    return SpotifyImportResult(name: name, tracks: tracks);
  }

  static List<List<String>> _parseCsv(String s) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
