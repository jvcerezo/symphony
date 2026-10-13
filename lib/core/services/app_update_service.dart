import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../utils/platform_url_launcher.dart';
import 'windows_auto_updater.dart';

class AppReleaseInfo {
  final String tagName;
  final String title;
  final String releaseNotes;
  final String htmlUrl;
  final String? windowsDownloadUrl;
  final String? androidDownloadUrl;
  final String? macDownloadUrl;
  final String? iosDownloadUrl;
  final DateTime? publishedAt;

  const AppReleaseInfo({
    required this.tagName,
    required this.title,
    required this.releaseNotes,
    required this.htmlUrl,
    this.windowsDownloadUrl,
    this.androidDownloadUrl,
    this.macDownloadUrl,
    this.iosDownloadUrl,
    this.publishedAt,
  });

  /// Version for display, e.g. "v1.0.29". CI publishes every build under
  /// the tag "latest" and puts the version in the title, so read the tag
  /// first and fall back to the title.
  String get displayVersion {
    final pattern = RegExp(r'v?(\d+\.\d+(?:\.\d+)?)');
    final match = pattern.firstMatch(tagName) ?? pattern.firstMatch(title);
    return match != null ? 'v${match.group(1)}' : tagName;
  }

  /// [releaseNotes] as readable lines. Markdown is flattened (bold, code
  /// and links become plain text) and CI boilerplate is dropped: the
  /// heading, commit hash, download links (the dialog has buttons for
  /// those) and the landing page link. Empty when nothing is left.
  List<String> get displayNotes => cleanReleaseNotes(releaseNotes);

  static final _boilerplate = RegExp(
    r'^(commit|windows desktop|android apk|landing page|download)\b',
    caseSensitive: false,
  );

  static List<String> cleanReleaseNotes(String body) {
    final lines = <String>[];
    for (final raw in body.split(RegExp(r'\r?\n'))) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      line = line
          .replaceFirst(RegExp(r'^[-*+]\s+'), '')
          .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
          .replaceAll(RegExp(r'\*\*|__|`'), '')
          .replaceAll(RegExp(r'https?://\S+'), '')
          .trim();
      if (line.isEmpty || _boilerplate.hasMatch(line)) continue;
      lines.add(line);
    }
    return lines;
  }

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? winUrl;
    String? apkUrl;
    String? macUrl;
    String? ipaUrl;

    final rawAssets = json['assets'] as List<dynamic>? ?? [];
    for (final a in rawAssets) {
      if (a is Map) {
        final name = (a['name']?.toString() ?? '').toLowerCase();
        final download = a['browser_download_url']?.toString();
        if (download != null) {
          // Releases also carry a macOS .zip, so a .zip is only the
          // Windows build when its name doesn't say otherwise.
          if (name.endsWith('.apk')) {
            apkUrl = download;
          } else if (name.endsWith('.ipa')) {
            ipaUrl = download;
          } else if (name.endsWith('.zip') && (name.contains('macos') || name.contains('mac-'))) {
            macUrl = download;
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
      macDownloadUrl: macUrl,
      iosDownloadUrl: ipaUrl,
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
  final bool isDownloading;
  final double downloadProgress;
  final bool isInstalling;

  const AppUpdateState({
    this.isChecking = false,
    this.hasUpdate = false,
    this.latestRelease,
    this.errorMessage,
    this.userNotified = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.isInstalling = false,
  });

  AppUpdateState copyWith({
    bool? isChecking,
    bool? hasUpdate,
    AppReleaseInfo? latestRelease,
    String? errorMessage,
    bool? userNotified,
    bool? isDownloading,
    double? downloadProgress,
    bool? isInstalling,
  }) {
    return AppUpdateState(
      isChecking: isChecking ?? this.isChecking,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      latestRelease: latestRelease ?? this.latestRelease,
      errorMessage: errorMessage ?? this.errorMessage,
      userNotified: userNotified ?? this.userNotified,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isInstalling: isInstalling ?? this.isInstalling,
    );
  }
}

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  /// Set by CI (`--dart-define=SYMPHONY_VERSION=1.0.<run number>`) and
  /// matched against the release title. Local builds report 1.0.0.
  static const String currentVersion = String.fromEnvironment('SYMPHONY_VERSION', defaultValue: '1.0.0');
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

  /// Downloads the Windows update bundle with progress tracking and applies the hot-swap
  Future<void> downloadAndApplyWindowsUpdate([String? directUrl]) async {
    final targetUrl = directUrl ?? state.latestRelease?.windowsDownloadUrl;
    if (targetUrl == null || targetUrl.isEmpty) {
      state = state.copyWith(errorMessage: 'No Windows update download available.');
      return;
    }

    if (state.isDownloading || state.isInstalling) return;

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      isInstalling: false,
      errorMessage: null,
    );

    try {
      await platformWindowsAutoUpdate(
        targetUrl,
        onProgress: (progress) {
          state = state.copyWith(
            downloadProgress: progress,
          );
        },
        onInstalling: () {
          state = state.copyWith(
            isDownloading: false,
            isInstalling: true,
          );
        },
      );
    } catch (e) {
      developer.log('Auto-update failed: $e', name: 'AppUpdateService');
      state = state.copyWith(
        isDownloading: false,
        isInstalling: false,
        errorMessage: 'Auto-update failed: $e',
      );
    }
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
