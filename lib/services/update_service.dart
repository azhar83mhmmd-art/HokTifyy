import 'package:streambeats/core/config/app_config.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import 'dart:convert';

import 'package:streambeats/core/constants/setting_keys.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/screens/widgets/snackbar.dart';
import 'package:streambeats/services/db/dao/settings_dao.dart';
import 'package:streambeats/services/db/db_provider.dart';
import 'package:streambeats/services/streambeats_updater_tools.dart'
    show isUpdateAvailable;

/// Pengamat siklus hidup aplikasi: memicu cek update tiap kali aplikasi
/// kembali ke layar depan.
class _UpdateLifecycleHook with WidgetsBindingObserver {
  _UpdateLifecycleHook(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Cek update lewat GitHub Releases dan tampilkan pop-up TERUS-MENERUS
/// selama versi terpasang masih lebih lama dari rilis terbaru:
///  - saat aplikasi dibuka,
///  - setiap kali aplikasi kembali dari latar belakang,
///  - berkala tiap 20 menit selama aplikasi terbuka.
/// Tombol "Nanti" hanya menunda sampai pemicu berikutnya; pop-up tidak
/// akan berhenti muncul sebelum aplikasi diperbarui.
class UpdateService {
  UpdateService._();

  static GlobalKey<NavigatorState>? _navKey;
  static _UpdateLifecycleHook? _hook;
  static Timer? _timer;
  static bool _checking = false;
  static bool _dialogShowing = false;
  static DateTime? _lastCheck;

  static const Duration _minGap = Duration(seconds: 45);
  static const Duration _periodic = Duration(minutes: 20);

  /// Panggil sekali dari root app (GlobalEventListener). Aman dipanggil ulang.
  static void start(GlobalKey<NavigatorState> navigatorKey) {
    _navKey = navigatorKey;
    if (_hook != null) return;
    _hook = _UpdateLifecycleHook(() => checkNow());
    WidgetsBinding.instance.addObserver(_hook!);
    _timer = Timer.periodic(_periodic, (_) => checkNow(force: true));
    // Beri waktu UI + navigator siap sebelum cek pertama.
    Future.delayed(const Duration(seconds: 3), () => checkNow(force: true));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    if (_hook != null) {
      WidgetsBinding.instance.removeObserver(_hook!);
      _hook = null;
    }
  }

  /// Kompatibilitas dengan pemanggil lama.
  static Future<void> checkUpdate(BuildContext context) =>
      checkNow(force: true);

  static Future<void> checkNow({bool force = false}) async {
    if (!AppConfig.updatesEnabled) return;
    if (_checking || _dialogShowing) return;
    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < _minGap) {
      return;
    }
    _checking = true;
    _lastCheck = now;

    try {
      // Hormati pengaturan "Beritahu pembaruan" (default: aktif).
      final notify = await SettingsDAO(DBProvider.db)
              .getSettingBool(SettingKeys.autoUpdateNotify) ??
          true;
      if (!notify) return;

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
      final String serverBuild = tagParts.length > 1 ? tagParts[1] : '0';
      final String webUrl =
          (data['html_url'] as String?) ?? AppConfig.websiteUrl;
      final String body = ((data['body'] as String?) ?? '').trim();
      final String changelog =
          body.isNotEmpty ? body : 'Pembaruan versi terbaru.';

      String apkUrl = '';
      for (final asset in (data['assets'] as List? ?? const [])) {
        final u = asset['browser_download_url']?.toString() ?? '';
        if (u.endsWith('.apk') && u.contains('universal')) {
          apkUrl = u;
          break;
        }
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final hasUpdate = isUpdateAvailable(
        packageInfo.version,
        packageInfo.buildNumber,
        serverVersion.isNotEmpty ? serverVersion : '0.0.0',
        serverBuild,
      );
      if (!hasUpdate) return;

      final ctx = _navKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        showUpdateDialog(ctx, serverVersion, webUrl, apkUrl, changelog);
      }
    } catch (e) {
      // Gagal diam-diam; akan dicoba lagi pada pemicu berikutnya.
      debugPrint('Error checking update: $e');
    } finally {
      _checking = false;
    }
  }

  static void showUpdateDialog(
    BuildContext context,
    String serverVersion,
    String webUrl,
    String apkUrl,
    String changelog,
  ) {
    if (_dialogShowing) return; // cegah pop-up bertumpuk
    _dialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Default_Theme.surfaceColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: Default_Theme.brandGradient,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pembaruan Tersedia',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'HokTifyy v$serverVersion',
                            style: TextStyle(
                              color: Default_Theme.accentColor2
                                  .withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Apa yang baru',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 190),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        changelog,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pengingat ini akan muncul lagi sampai aplikasi diperbarui.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Default_Theme.accentColor2,
                      foregroundColor: const Color(0xFF2E1A66),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text(
                      'Perbarui Sekarang',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      if (apkUrl.isEmpty) {
                        _openWeb(webUrl);
                      } else {
                        _startInAppDownload(context, apkUrl, serverVersion);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text('Nanti',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6))),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _openWeb(webUrl);
                        },
                        child: Text('Buka Web',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => _dialogShowing = false);
  }

  static Future<void> _openWeb(String webUrl) async {
    final uri = Uri.parse(webUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static void _startInAppDownload(
      BuildContext context, String apkUrl, String version) {
    if (apkUrl.isEmpty) {
      SnackbarService.showMessage('Link download APK tidak valid.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _DownloadProgressDialog(apkUrl: apkUrl, version: version),
    );
  }
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
          final file = File('${tempDir.path}/HokTifyy_v${widget.version}.apk');
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
