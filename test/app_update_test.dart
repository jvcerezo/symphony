import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/services/app_update_service.dart';

void main() {
  group('AppUpdateNotifier Version Comparison', () {
    test('Identifies patch, minor, and major newer versions accurately', () {
      expect(AppUpdateNotifier.isNewerVersion('v1.0.1', '1.0.0'), isTrue);
      expect(AppUpdateNotifier.isNewerVersion('v1.1.0', '1.0.0'), isTrue);
      expect(AppUpdateNotifier.isNewerVersion('v2.0.0', '1.0.0'), isTrue);
      expect(AppUpdateNotifier.isNewerVersion('1.0.5', '1.0.0'), isTrue);
    });

    test('Returns false when remote version is equal or older', () {
      expect(AppUpdateNotifier.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(AppUpdateNotifier.isNewerVersion('v0.9.9', '1.0.0'), isFalse);
      expect(AppUpdateNotifier.isNewerVersion('v0.8.0', '1.0.0'), isFalse);
      expect(AppUpdateNotifier.isNewerVersion('', '1.0.0'), isFalse);
    });

    test('Extracts version from release title when remote tag is "latest"', () {
      expect(
        AppUpdateNotifier.isNewerVersion('latest', '1.0.0', remoteTitle: 'Symphony v1.0.4 Release'),
        isTrue,
      );
      expect(
        AppUpdateNotifier.isNewerVersion('latest', '1.0.0', remoteTitle: 'Symphony 1.0.0 (Auto-Build)'),
        isFalse,
      );
      expect(
        AppUpdateNotifier.isNewerVersion('latest', '1.0.0', remoteTitle: 'Symphony v0.9.0'),
        isFalse,
      );
    });
  });

  group('AppReleaseInfo JSON Parsing', () {
    test('Parses GitHub API release payload and extracts platform binary assets', () {
      const mockJson = '''
      {
        "tag_name": "v1.0.2",
        "name": "Symphony v1.0.2 (Architecture & Offline Update)",
        "body": "## Changes\\n- Client-side offline resolution\\n- Monochrome design",
        "html_url": "https://github.com/jvcerezo/symphony/releases/tag/v1.0.2",
        "published_at": "2026-10-06T12:00:00Z",
        "assets": [
          {
            "name": "symphony.apk",
            "browser_download_url": "https://github.com/jvcerezo/symphony/releases/download/v1.0.2/symphony.apk"
          },
          {
            "name": "symphony-windows-x64.zip",
            "browser_download_url": "https://github.com/jvcerezo/symphony/releases/download/v1.0.2/symphony-windows-x64.zip"
          }
        ]
      }
      ''';

      final data = jsonDecode(mockJson) as Map<String, dynamic>;
      final release = AppReleaseInfo.fromJson(data);

      expect(release.tagName, equals('v1.0.2'));
      expect(release.title, equals('Symphony v1.0.2 (Architecture & Offline Update)'));
      expect(release.htmlUrl, equals('https://github.com/jvcerezo/symphony/releases/tag/v1.0.2'));
      expect(release.androidDownloadUrl, equals('https://github.com/jvcerezo/symphony/releases/download/v1.0.2/symphony.apk'));
      expect(release.windowsDownloadUrl, equals('https://github.com/jvcerezo/symphony/releases/download/v1.0.2/symphony-windows-x64.zip'));
      expect(release.publishedAt, isNotNull);
    });

    test('the macOS zip is never taken for the Windows update', () {
      AppReleaseInfo parse(List<String> names) => AppReleaseInfo.fromJson({
            'tag_name': 'latest',
            'assets': [
              for (final n in names) {'name': n, 'browser_download_url': 'https://dl/$n'},
            ],
          });

      for (final order in [
        ['symphony-windows-x64.zip', 'symphony-macos.zip', 'symphony-ios.ipa', 'symphony.apk'],
        ['symphony-ios.ipa', 'symphony-macos.zip', 'symphony.apk', 'symphony-windows-x64.zip'],
      ]) {
        final release = parse(order);
        expect(release.windowsDownloadUrl, 'https://dl/symphony-windows-x64.zip');
        expect(release.macDownloadUrl, 'https://dl/symphony-macos.zip');
        expect(release.iosDownloadUrl, 'https://dl/symphony-ios.ipa');
        expect(release.androidDownloadUrl, 'https://dl/symphony.apk');
      }
    });

    test('Gracefully handles release with missing assets', () {
      const mockJson = '''
      {
        "tag_name": "v1.0.0",
        "name": "Initial Release",
        "body": "Initial",
        "html_url": "https://github.com/jvcerezo/symphony/releases/tag/v1.0.0",
        "assets": []
      }
      ''';

      final data = jsonDecode(mockJson) as Map<String, dynamic>;
      final release = AppReleaseInfo.fromJson(data);

      expect(release.windowsDownloadUrl, isNull);
      expect(release.androidDownloadUrl, isNull);
      expect(release.htmlUrl, equals('https://github.com/jvcerezo/symphony/releases/tag/v1.0.0'));
    });
  });

  group('AppUpdateState', () {
    test('Initial state is correct and copyWith preserves properties', () {
      const state = AppUpdateState();
      expect(state.isChecking, isFalse);
      expect(state.hasUpdate, isFalse);
      expect(state.latestRelease, isNull);
      expect(state.userNotified, isFalse);
      expect(state.isDownloading, isFalse);
      expect(state.downloadProgress, equals(0.0));
      expect(state.isInstalling, isFalse);

      final updated = state.copyWith(
        hasUpdate: true,
        userNotified: true,
        isDownloading: true,
        downloadProgress: 0.65,
        isInstalling: false,
      );
      expect(updated.hasUpdate, isTrue);
      expect(updated.userNotified, isTrue);
      expect(updated.isChecking, isFalse);
      expect(updated.isDownloading, isTrue);
      expect(updated.downloadProgress, equals(0.65));
      expect(updated.isInstalling, isFalse);

      final installing = updated.copyWith(
        isDownloading: false,
        isInstalling: true,
      );
      expect(installing.isDownloading, isFalse);
      expect(installing.isInstalling, isTrue);
    });
  });

  group('Release display', () {
    const ciBody = '''## 🎵 Symphony Release Distribution
- **Commit**: `73f38d79fa2f85898c86ad2bdc5b844682ed8805`
- **Windows Desktop (x64)**: [Download symphony-windows-x64.zip](https://github.com/jvcerezo/symphony/releases/download/latest/symphony-windows-x64.zip)
- **Android APK**: [Download symphony.apk](https://github.com/jvcerezo/symphony/releases/download/latest/symphony.apk)
- **Landing Page**: https://symphony.jettimothycerezo.dev''';

    test('drops the CI boilerplate entirely', () {
      expect(AppReleaseInfo.cleanReleaseNotes(ciBody), isEmpty);
    });

    test('keeps real notes as plain text', () {
      const body = '''## What's new
- **Lyrics** that follow the song
- Fixed [shuffle](https://example.com/pr/1) doing nothing
* `Queue` can be reordered''';
      expect(AppReleaseInfo.cleanReleaseNotes(body), [
        'Lyrics that follow the song',
        'Fixed shuffle doing nothing',
        'Queue can be reordered',
      ]);
    });

    test('shows the version from the title when the tag is "latest"', () {
      const release = AppReleaseInfo(tagName: 'latest', title: 'Symphony v1.0.29', releaseNotes: '', htmlUrl: '');
      expect(release.displayVersion, 'v1.0.29');
      const tagged = AppReleaseInfo(tagName: 'v2.1.0', title: 'Symphony v2.1.0', releaseNotes: '', htmlUrl: '');
      expect(tagged.displayVersion, 'v2.1.0');
    });
  });
}
