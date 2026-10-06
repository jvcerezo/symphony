import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_update_service.dart';
import '../theme/symphony_theme.dart';
import 'symphony_brand_logo.dart';

/// Modal dialog displaying details about an available Symphony update
class AppUpdateDialog extends ConsumerWidget {
  final AppReleaseInfo release;

  const AppUpdateDialog({
    super.key,
    required this.release,
  });

  static Future<void> show(BuildContext context, AppReleaseInfo release) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AppUpdateDialog(release: release),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final winUrl = release.windowsDownloadUrl;
    final apkUrl = release.androidDownloadUrl;

    return Dialog(
      backgroundColor: const Color(0xFF0F0F12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF27272A), width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SymphonyBrandLogo(size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SOFTWARE UPDATE AVAILABLE',
                          style: TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          release.title.isNotEmpty ? release.title : 'Symphony Update',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: SymphonyTheme.textSecondary, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // 2. Version comparison badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF27272A)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Installed: ',
                      style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 12),
                    ),
                    const Text(
                      'v${AppUpdateNotifier.currentVersion}',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.arrow_forward_rounded, color: SymphonyTheme.textMuted, size: 14),
                    ),
                    const Text(
                      'Latest: ',
                      style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 12),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        release.tagName,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. Release Notes / Changes
              const Text(
                'RELEASE NOTES',
                style: TextStyle(
                  color: SymphonyTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF222225)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      release.releaseNotes.isNotEmpty
                          ? release.releaseNotes
                          : 'Includes new features, audio caching updates, performance optimizations, and stability improvements.',
                      style: const TextStyle(
                        color: Color(0xFFD4D4D8),
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 4. Download / Action Buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Windows Download (if available, or if on desktop)
                  if (winUrl != null || (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)) ...[
                    ElevatedButton.icon(
                      onPressed: () {
                        final target = winUrl ?? release.htmlUrl;
                        AppUpdateNotifier.openUrl(target);
                      },
                      icon: const Icon(Icons.desktop_windows_rounded, size: 18),
                      label: Text(winUrl != null ? 'Download Windows (.zip)' : 'Get Windows Update'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Android Download (if available)
                  if (apkUrl != null) ...[
                    OutlinedButton.icon(
                      onPressed: () => AppUpdateNotifier.openUrl(apkUrl),
                      icon: const Icon(Icons.android_rounded, size: 18, color: Colors.white),
                      label: const Text('Download Android (.apk)', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF3F3F46)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // View on GitHub Releases
                  TextButton.icon(
                    onPressed: () => AppUpdateNotifier.openUrl(release.htmlUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16, color: SymphonyTheme.textSecondary),
                    label: const Text(
                      'View Details on GitHub Releases',
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact, elegant top banner displayed when an update is available
class AppUpdateBanner extends ConsumerWidget {
  final VoidCallback onDismiss;

  const AppUpdateBanner({
    super.key,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(appUpdateProvider);
    final release = updateState.latestRelease;

    if (!updateState.hasUpdate || release == null || updateState.userNotified) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF27272A), width: 1),
      ),
      child: Row(
        children: [
          const SymphonyBrandLogo(size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Colors.white),
                children: [
                  const TextSpan(
                    text: 'A new version of Symphony (',
                    style: TextStyle(color: Color(0xFFA1A1AA)),
                  ),
                  TextSpan(
                    text: release.tagName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const TextSpan(
                    text: ') is ready.',
                    style: TextStyle(color: Color(0xFFA1A1AA)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => AppUpdateDialog.show(context, release),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'View Update',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: const Icon(Icons.close, size: 14, color: SymphonyTheme.textSecondary),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
