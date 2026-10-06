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

      final updated = state.copyWith(
        hasUpdate: true,
        userNotified: true,
      );
      expect(updated.hasUpdate, isTrue);
      expect(updated.userNotified, isTrue);
      expect(updated.isChecking, isFalse);
    });
  });
}
