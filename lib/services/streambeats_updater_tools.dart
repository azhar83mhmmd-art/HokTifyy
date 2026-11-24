import 'package:streambeats/core/config/app_config.dart';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:streambeats/core/constants/setting_keys.dart';
import 'package:streambeats/services/db/db_provider.dart';
import 'package:streambeats/services/db/dao/settings_dao.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

bool isUpdateAvailable(
    String currentVer, String currentBuild, String newVer, String newBuild,
    {bool checkBuild = true}) {
  List<int> parseVersion(String v) {
    v = v.replaceFirst(RegExp(r'^v'), '');
    final parts = v.split('.');
    return parts.map((p) {
      final m = RegExp(r'^(\d+)').firstMatch(p);
      return m != null ? int.parse(m.group(1)!) : 0;
    }).toList();
  }

  List<int> currentParts = parseVersion(currentVer);
  List<int> newParts = parseVersion(newVer);

  final maxLen = currentParts.length > newParts.length
      ? currentParts.length
      : newParts.length;
  for (int i = 0; i < maxLen; i++) {
    final cur = i < currentParts.length ? currentParts[i] : 0;
    final neu = i < newParts.length ? newParts[i] : 0;
    if (neu > cur) return true;
    if (neu < cur) return false;
  }

  if (checkBuild && !Platform.isLinux) {
    int parseBuild(String b) {
      try {
        final parsed = int.parse(b);
        return parsed > 1000 ? parsed % 1000 : parsed;
      } catch (_) {
        final m = RegExp(r'(\d+)').firstMatch(b);
        return m != null ? int.parse(m.group(1)!) : 0;
      }
    }

    final curBuild = parseBuild(currentBuild);
    final newBuildNum = parseBuild(newBuild);
    if (newBuildNum > curBuild) return true;
    if (newBuildNum < curBuild) return false;
  }

  return false;
}

Future<Map<String, dynamic>> githubUpdate(
    {Duration timeout = const Duration(seconds: 6)}) async {
  if (!AppConfig.updatesEnabled) {
    throw Exception('Update check disabled (HOKTIFYY_REPO not set)');
  }
  final url =
      'https://api.github.com/repos/${AppConfig.githubRepo}/releases/latest';
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  try {
    final response = await http.get(Uri.parse(url)).timeout(timeout);
    log("GitHub response status code: ${response.statusCode}",
        name: 'UpdaterTools');
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      final tag = (data['tag_name'] as String?) ?? '';
      final tagParts = tag.split('+');
      final versionPart =
          tagParts.isNotEmpty ? tagParts[0].replaceFirst('v', '') : '';
      final buildPart = tagParts.length > 1 ? tagParts[1] : '';

      String? download = extractUpUrl(data);
      download ??= data['html_url'] ?? '';

      return {
        'source': 'github',
        'newVer': versionPart,
        'newBuild': buildPart,
        'download_url': download,
        'currVer': packageInfo.version,
        'currBuild': (int.tryParse(packageInfo.buildNumber) ?? 0) > 1000
            ? ((int.tryParse(packageInfo.buildNumber) ?? 0) % 1000).toString()
            : packageInfo.buildNumber,
        'results': isUpdateAvailable(
          packageInfo.version,
          packageInfo.buildNumber,
          versionPart.isNotEmpty ? versionPart : '0.0.0',
          buildPart.isNotEmpty ? buildPart : '0',
          checkBuild: true,
        ),
      };
    } else {
      throw Exception('GitHub returned ${response.statusCode}');
    }
  } catch (e, st) {
    log('GitHub update check failed: $e\n$st', name: 'UpdaterTools');
    rethrow;
  }
}

Future<Map<String, dynamic>> getAppUpdates() async {
  Map<String, dynamic> updates;
  try {
    updates = await githubUpdate();
  } catch (e) {
    // Vynora Music hanya memakai GitHub Releases milik repo sendiri
    // (SourceForge/upstream StreamBeats tidak dipakai lagi).
    log('GitHub check failed: $e', name: 'UpdaterTools');
    {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        updates = {
          'results': false,
          'error': 'Failed to check remote releases',
          'currVer': packageInfo.version,
          'currBuild': packageInfo.buildNumber,
          'source': 'none',
        };
      } catch (e3) {
        updates = {
          'results': false,
          'error':
              'Failed to check remote releases and failed to read local package info',
          'source': 'none',
        };
      }
    }
  }

  try {
    final readChangelogs = await SettingsDAO(DBProvider.db)
        .getSettingStr(SettingKeys.readChangelogs);
    final currVer = "v${updates['currVer']}";
    final newVer = "v${updates['newVer']}";

    log('Current version: $currVer, New version: $newVer, Read changelogs: $readChangelogs',
        name: 'UpdaterTools');

    if (currVer == newVer &&
        (readChangelogs == null || readChangelogs != currVer)) {
      final changelogText = await fetchChangelog();
      updates['changelogs'] = changelogText ?? '';
    } else {
      updates['changelogs'] = null;
    }
  } catch (e, st) {
    log('Attaching changelog failed: $e\n$st', name: 'UpdaterTools');
    updates['changelogs'] = null;
  }

  return updates;
}

Future<String?> fetchChangelog(
    {Duration timeout = const Duration(seconds: 6)}) async {
  if (!AppConfig.updatesEnabled) return null;
  final githubRawUrl =
      'https://raw.githubusercontent.com/${AppConfig.githubRepo}/main/CHANGELOG.md';
  try {
    final response = await http.get(Uri.parse(githubRawUrl)).timeout(timeout);

    if (response.statusCode == 200 &&
        !response.body.trim().startsWith('<') &&
        !response.body.contains('<!DOCTYPE') &&
        response.body.contains('## [')) {
      return response.body;
    } else {
      log('Changelog fetch returned non-markdown content',
          name: 'UpdaterTools');
      return null;
    }
  } catch (e, st) {
    log('Failed to fetch changelog: $e\n$st', name: 'UpdaterTools');
    return null;
  }
}

Future<Map<String, dynamic>> getLatestVersion() async => await getAppUpdates();

String? extractUpUrl(Map<String, dynamic> data) {

  // Android: pilih APK universal supaya cocok di semua arsitektur.
  if (Platform.isAndroid) {
    for (var element in (data["assets"] as List)) {
      final u = element["browser_download_url"].toString();
      if (u.contains("android") && u.contains("universal")) return u;
    }
  }
  for (var element in (data["assets"] as List)) {
    if (element["browser_download_url"].toString().contains("windows")) {
      if (Platform.isWindows) {
        return element["browser_download_url"].toString();
      }
    } else if (element["browser_download_url"].toString().contains("android")) {
      if (Platform.isAndroid) {
        return element["browser_download_url"].toString();
      }
    } else {
      continue;
    }
  }
  return null;
}