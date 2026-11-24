import 'package:streambeats/core/config/app_config.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import 'dart:convert';

import 'package:streambeats/routes/app_router.dart';
import 'package:streambeats/screens/widgets/snackbar.dart';

class UpdateService {
  /// Dialog update sedang tampil -> jangan tumpuk dialog kedua.
  static bool _dialogShowing = false;

  /// Update terakhir yang diketahui. Selama belum dipasang, dialog akan
  /// muncul lagi setiap aplikasi dibuka / dilanjutkan / beranda dibuka.
  static _PendingUpdate? _pending;

  static bool _checking = false;
  static DateTime? _lastCheck;

  static BuildContext? _resolveContext(BuildContext? context) {
    final navContext = AppRouter.globalRouterKey.currentContext;
    if (navContext != null && navContext.mounted) return navContext;
    if (context != null && context.mounted) return context;
    return null;
  }

  /// Cek update lewat GitHub Releases. Dipanggil saat aplikasi start, saat
  /// aplikasi dilanjutkan (resume), dan saat beranda dibuka.
  ///
  /// Tidak ada lagi "sekali per sesi": selama versi terpasang lebih lama dari
  /// rilis terbaru, pop up akan terus muncul sampai pengguna memperbarui.
  /// Aktif hanya jika dibuild dengan --dart-define=HOKTIFYY_REPO=user/repo.
  static Future<void> checkUpdate([BuildContext? context]) async {
    if (!AppConfig.updatesEnabled) return;

    // Update sudah diketahui -> tampilkan lagi langsung tanpa request jaringan.
    final pending = _pending;
    if (pending != null) {
      _showPending(context, pending);
      return;
    }

    if (_checking) return;
    final last = _lastCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _checking = true;
    _lastCheck = DateTime.now();

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/${AppConfig.githubRepo}/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final String tag = (data['tag_name'] as String?) ?? '';
      final tagParts = tag.replaceFirst(RegExp(r'^v'), '').split('+');
      final String serverVersion = tagParts.first;
      final int serverBuild =
          tagParts.length > 1 ? (int.tryParse(tagParts[1]) ?? 0) : 0;
      final String webUrl =
          (data['html_url'] as String?) ?? AppConfig.websiteUrl;
      final String changelog =
          ((data['body'] as String?) ?? '').trim().isNotEmpty
              ? (data['body'] as String).trim()
              : 'Pembaruan versi terbaru.';

      String apkUrl = '';
      for (final asset in (data['assets'] as List? ?? const [])) {
        final u = asset['browser_download_url']?.toString() ?? '';
        if (u.endsWith('.apk') && u.contains('universal')) {
          apkUrl = u;
          break;
        }
      }

      final packageInfo = await PackageInfo.fromPlatform();
      // Pada APK per-ABI, Flutter menambah offset 1000/2000/4000 ke versionCode.
      final int rawBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final int currentBuild = rawBuild > 1000 ? rawBuild % 1000 : rawBuild;

      if (serverBuild > currentBuild) {
        final update = _PendingUpdate(
            serverVersion, webUrl, apkUrl, changelog);
        _pending = update;
        _showPending(context, update);
      } else {
        _pending = null;
      }
    } catch (e) {
      // Gagal diam-diam agar tidak mengganggu pengguna
      debugPrint('Error checking update: $e');
    } finally {
      _checking = false;
    }
  }

  static void _showPending(BuildContext? context, _PendingUpdate u) {
    final ctx = _resolveContext(context);
    if (ctx == null) return;
    showUpdateDialog(ctx, u.version, u.webUrl, u.apkUrl, u.changelog);
  }

  static void showUpdateDialog(
    BuildContext context,
    String serverVersion,
    String webUrl,
    String apkUrl,
    String changelog,
  ) {
    if (_dialogShowing) return;
    _dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Colors.purpleAccent, size: 28),
            const SizedBox(width: 10),
            Text(
              'Pembaruan Tersedia v$serverVersion',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Apa yang baru:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              changelog,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pilih metode untuk memperbarui aplikasi Anda.',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nanti', style: TextStyle(color: Colors.grey)),
          ),
          // Option 1: Open Official Web
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(webUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Web', style: TextStyle(color: Colors.grey)),
          ),
          // Option 2: Download inside application
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _startInAppDownload(context, apkUrl, serverVersion);
            },
            child: const Text('Perbarui Langsung', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).whenComplete(() => _dialogShowing = false);
  }

  static void _startInAppDownload(BuildContext context, String apkUrl, String version) {
    if (apkUrl.isEmpty) {
      SnackbarService.showMessage('Link download APK tidak valid.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(apkUrl: apkUrl, version: version),
    );
  }
}

class _PendingUpdate {
  final String version;
  final String webUrl;
  final String apkUrl;
  final String changelog;
  const _PendingUpdate(this.version, this.webUrl, this.apkUrl, this.changelog);
}

class _DownloadProgressDialog extends StatefulWidget {
  final String apkUrl;
  final String version;

  const _DownloadProgressDialog({
    Key? key,
    required this.apkUrl,
    required this.version,
  }) : super(key: key);

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double progress = 0.0;
  String progressText = "Menghubungkan...";
  late http.Client client;
  bool _downloadStarted = false;

  @override
  void initState() {
    super.initState();
    client = http.Client();
    _startDownload();
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_downloadStarted) return;
    _downloadStarted = true;

    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.status;
        if (status.isDenied) {
          await Permission.requestInstallPackages.request();
        }
      }

      final request = http.Request('GET', Uri.parse(widget.apkUrl));
      final response = await client.send(request).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Gagal menghubungi server update: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final List<int> bytes = [];

      response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (contentLength > 0 && mounted) {
            setState(() {
              progress = bytes.length / contentLength;
              progressText = "Mengunduh... ${(progress * 100).toStringAsFixed(0)}%";
            });
          }
        },
        onDone: () async {
          if (!mounted) return;
          setState(() {
            progressText = "Menyimpan file...";
          });

          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/VynoraMusic_v${widget.version}.apk');
          await file.writeAsBytes(bytes);

          if (!mounted) return;
          setState(() {
            progressText = "Memasang aplikasi...";
          });

          Navigator.pop(context); // Close the download dialog

          final openResult = await OpenFile.open(file.path);
          if (openResult.type != ResultType.done) {
            SnackbarService.showMessage('Gagal membuka file APK: ${openResult.message}');
          }
        },
        onError: (e) {
          if (mounted) {
            Navigator.pop(context);
          }
          SnackbarService.showMessage('Gagal mengunduh: $e');
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      SnackbarService.showMessage('Gagal mengunduh update: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161618),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Mengunduh Pembaruan',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            color: Colors.purpleAccent,
            backgroundColor: Colors.white10,
          ),
          const SizedBox(height: 16),
          Text(
            progressText,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
