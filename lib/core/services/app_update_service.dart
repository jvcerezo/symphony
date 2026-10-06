import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../utils/platform_url_launcher.dart';

class AppReleaseInfo {
  final String tagName;
  final String title;
  final String releaseNotes;
  final String htmlUrl;
  final String? windowsDownloadUrl;
  final String? androidDownloadUrl;
  final DateTime? publishedAt;

  const AppReleaseInfo({
    required this.tagName,
    required this.title,
    required this.releaseNotes,
    required this.htmlUrl,
    this.windowsDownloadUrl,
    this.androidDownloadUrl,
    this.publishedAt,
  });

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? winUrl;
    String? apkUrl;

    final rawAssets = json['assets'] as List<dynamic>? ?? [];
    for (final a in rawAssets) {
      if (a is Map) {
        final name = (a['name']?.toString() ?? '').toLowerCase();
        final download = a['browser_download_url']?.toString();
        if (download != null) {
          if (name.endsWith('.apk')) {
            apkUrl = download;
          } else if (name.endsWith('.zip') || name.endsWith('.exe') || name.endsWith('.msi')) {
            winUrl = download;
          }
        }
      }
    }

    DateTime? pubDate;
    if (json['published_at'] != null) {
      pubDate = DateTime.tryParse(json['published_at'].toString());
    }

    return AppReleaseInfo(
      tagName: (json['tag_name']?.toString() ?? 'latest').trim(),
      title: (json['name']?.toString() ?? 'Latest Release').trim(),
      releaseNotes: (json['body']?.toString() ?? '').trim(),
      htmlUrl: (json['html_url']?.toString() ?? 'https://github.com/jvcerezo/symphony/releases').trim(),
      windowsDownloadUrl: winUrl,
      androidDownloadUrl: apkUrl,
      publishedAt: pubDate,
    );
  }
}

class AppUpdateState {
  final bool isChecking;
  final bool hasUpdate;
  final AppReleaseInfo? latestRelease;
  final String? errorMessage;
  final bool userNotified;

  const AppUpdateState({
    this.isChecking = false,
    this.hasUpdate = false,
    this.latestRelease,
    this.errorMessage,
    this.userNotified = false,
  });

  AppUpdateState copyWith({
    bool? isChecking,
    bool? hasUpdate,
    AppReleaseInfo? latestRelease,
    String? errorMessage,
    bool? userNotified,
  }) {
    return AppUpdateState(
      isChecking: isChecking ?? this.isChecking,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      latestRelease: latestRelease ?? this.latestRelease,
      errorMessage: errorMessage ?? this.errorMessage,
      userNotified: userNotified ?? this.userNotified,
    );
  }
}

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  static const String currentVersion = '1.0.0';
  static const String repoOwner = 'jvcerezo';
  static const String repoName = 'symphony';
  static const String apiUrl = 'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  final http.Client _httpClient;

  AppUpdateNotifier({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        super(const AppUpdateState()) {
    // Proactively check for updates in background
    checkForUpdates();
  }

  /// Checks GitHub Releases API for a newer tag
  Future<void> checkForUpdates() async {
    state = state.copyWith(isChecking: true, errorMessage: null);

    try {
      final response = await _httpClient.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Symphony-Music-App/$currentVersion',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final release = AppReleaseInfo.fromJson(data);

        final isNewer = isNewerVersion(
          release.tagName,
          currentVersion,
          remoteTitle: release.title,
        );

        state = state.copyWith(
          isChecking: false,
          hasUpdate: isNewer,
          latestRelease: release,
        );

        developer.log(
          'Update check result: current=$currentVersion, remote=${release.tagName}, hasUpdate=$isNewer',
          name: 'AppUpdateService',
        );
      } else {
        state = state.copyWith(
          isChecking: false,
          errorMessage: 'Server returned HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      developer.log('Update check failed: $e', name: 'AppUpdateService');
      state = state.copyWith(
        isChecking: false,
        errorMessage: e.toString(),
      );
    }
  }

  void markUserNotified() {
    state = state.copyWith(userNotified: true);
  }

  static bool isNewerVersion(String remoteTag, String localVersion, {String? remoteTitle}) {
    // 1. Try parsing version numbers from remoteTag (e.g. "v1.2.0" -> "1.2.0")
    var cleanRemote = remoteTag.replaceAll(RegExp(r'[^0-9.]'), '').trim();

    // 2. If tag was "latest" or didn't contain digits, try extracting from title (e.g. "Symphony 1.1.0")
    if (cleanRemote.isEmpty && remoteTitle != null) {
      final match = RegExp(r'v?(\d+\.\d+(?:\.\d+)?)').firstMatch(remoteTitle);
      if (match != null) {
        cleanRemote = match.group(1) ?? '';
      }
    }

    final cleanLocal = localVersion.replaceAll(RegExp(r'[^0-9.]'), '').trim();

    if (cleanRemote.isEmpty || cleanLocal.isEmpty) return false;
    if (cleanRemote == cleanLocal) return false;

    final remoteParts = cleanRemote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final localParts = cleanLocal.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final l = i < localParts.length ? localParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }

    return false;
  }

  static Future<bool> openUrl(String url, {bool isDownload = false}) async {
    return await platformLaunchUrl(url, isDownload: isDownload);
  }
}

final appUpdateProvider = StateNotifierProvider<AppUpdateNotifier, AppUpdateState>((ref) {
  return AppUpdateNotifier();
});
