import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/widgets/symphony_brand_logo.dart';
import '../../../audio_player/presentation/views/symphony_player_screen.dart';

/// The official public showcase & distribution landing page for Symphony.
/// Designed with an architectural, monochrome aesthetic (consistent with jettimothycerezo.dev).
class SymphonyLandingPage extends ConsumerWidget {
  const SymphonyLandingPage({super.key});

  static const String repoUrl = 'https://github.com/jvcerezo/symphony';
  static const String portfolioUrl = 'https://jettimothycerezo.dev';
  static const String fallbackWindowsUrl = 'https://github.com/jvcerezo/symphony/releases';
  static const String fallbackAndroidUrl = 'https://github.com/jvcerezo/symphony/releases/download/latest/symphony.apk';

  static void _openExternal(String url) {
    AppUpdateNotifier.openUrl(url);
  }

  void _launchWebPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const SymphonyPlayerScreen(isWebDemoMode: true),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(appUpdateProvider);
    final latestRelease = updateState.latestRelease;
    final versionTag = latestRelease?.tagName ?? 'v1.0.0';
    final hasDirectWindowsAsset = latestRelease?.windowsDownloadUrl != null;
    final winDownloadUrl = latestRelease?.windowsDownloadUrl ?? fallbackWindowsUrl;
    final apkDownloadUrl = latestRelease?.androidDownloadUrl ??
        (kIsWeb ? '/symphony.apk' : fallbackAndroidUrl);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 860;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 40 : 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Navigation Header
                    _buildNavBar(context, isDesktop, versionTag),

                    SizedBox(height: isDesktop ? 64 : 40),

                    // 2. Hero Section
                    _buildHeroSection(
                      context,
                      isDesktop,
                      versionTag,
                      hasDirectWindowsAsset,
                      winDownloadUrl,
                      apkDownloadUrl,
                    ),

                    SizedBox(height: isDesktop ? 80 : 56),

                    // 3. Platform Distribution Cards (Windows, Android, Web)
                    _buildDistributionGrid(
                      context,
                      isDesktop,
                      hasDirectWindowsAsset,
                      winDownloadUrl,
                      apkDownloadUrl,
                      versionTag,
                    ),

                    SizedBox(height: isDesktop ? 80 : 56),

                    // 4. Architectural Features Breakdown
                    _buildFeaturesSection(isDesktop),

                    SizedBox(height: isDesktop ? 80 : 56),

                    // 5. Minimalist Portfolio Footer
                    _buildFooter(context, isDesktop),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Navigation Bar
  Widget _buildNavBar(BuildContext context, bool isDesktop, String versionTag) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Brand Mark & Title
        Row(
          children: [
            const SymphonyBrandLogo(size: 32),
            const SizedBox(width: 12),
            const Text(
              'SYMPHONY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Text(
                versionTag,
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        // Action Buttons
        Row(
          children: [
            if (isDesktop) ...[
              TextButton.icon(
                onPressed: () => _openExternal(repoUrl),
                icon: const Icon(Icons.code_rounded, size: 16, color: Color(0xFFA1A1AA)),
                label: const Text(
                  'GitHub',
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
            ],
            OutlinedButton(
              onPressed: () => _launchWebPlayer(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3F3F46)),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Web Demo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // MARK: - Hero Section
  Widget _buildHeroSection(
    BuildContext context,
    bool isDesktop,
    String versionTag,
    bool hasDirectWindowsAsset,
    String winDownloadUrl,
    String apkDownloadUrl,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tagline Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: const Text(
            'OFFLINE-FIRST • CLIENT-SIDE RESOLUTION • ZERO ADS',
            style: TextStyle(
              color: Color(0xFFA1A1AA),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Hero Headline
        Text(
          'Sound, distilled.\nYour music, truly offline.',
          style: TextStyle(
            color: Colors.white,
            fontSize: isDesktop ? 54 : 36,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
            height: 1.08,
          ),
        ),

        const SizedBox(height: 18),

        // Subtext
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: const Text(
            'A minimalist music player built for people who want clean audio without algorithmic bloat. '
            'Streams are resolved natively on your client device and saved directly to your local drive for seamless playback anywhere.',
            style: TextStyle(
              color: Color(0xFFA1A1AA),
              fontSize: 16,
              height: 1.6,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Hero CTA Buttons
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: () => _openExternal(winDownloadUrl),
              icon: const Icon(Icons.desktop_windows_rounded, size: 18),
              label: Text(hasDirectWindowsAsset
                  ? 'Download for Windows ($versionTag)'
                  : 'Windows App (GitHub Releases)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _openExternal(apkDownloadUrl),
              icon: const Icon(Icons.android_rounded, size: 18, color: Colors.white),
              label: const Text('Download Android APK', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3F3F46)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            TextButton.icon(
              onPressed: () => _launchWebPlayer(context),
              icon: const Icon(Icons.open_in_browser_rounded, size: 18, color: Color(0xFFA1A1AA)),
              label: const Text(
                'Try Web Demo →',
                style: TextStyle(color: Color(0xFFA1A1AA), fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // MARK: - Distribution Cards
  Widget _buildDistributionGrid(
    BuildContext context,
    bool isDesktop,
    bool hasDirectWindowsAsset,
    String winDownloadUrl,
    String apkDownloadUrl,
    String versionTag,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISTRIBUTION PLATFORMS',
          style: TextStyle(
            color: Color(0xFFA1A1AA),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = isDesktop ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // 1. Windows Desktop Card
                _buildPlatformCard(
                  width: cardWidth,
                  icon: Icons.desktop_windows_rounded,
                  title: 'Windows Desktop',
                  badge: hasDirectWindowsAsset ? 'Portable .zip' : 'GitHub Releases',
                  spec: 'Windows 10 / 11 • 64-bit',
                  description:
                      'Full client-side stream resolution, hardware media keys, system tray, and unlimited local hard drive audio caching.',
                  buttonText: hasDirectWindowsAsset ? 'Download .zip' : 'View on GitHub',
                  isPrimary: true,
                  onTap: () => _openExternal(winDownloadUrl),
                ),

                // 2. Android Mobile Card
                _buildPlatformCard(
                  width: cardWidth,
                  icon: Icons.android_rounded,
                  title: 'Android Mobile',
                  badge: 'Native APK',
                  spec: 'Android 8.0+ (Oreo+)',
                  description:
                      'Lockscreen media session, background playback service, offline track management, and touch-optimized navigation.',
                  buttonText: 'Download .apk',
                  isPrimary: false,
                  onTap: () => _openExternal(apkDownloadUrl),
                ),

                // 3. Web Player Card
                _buildPlatformCard(
                  width: cardWidth,
                  icon: Icons.language_rounded,
                  title: 'Web Player Demo',
                  badge: 'Browser',
                  spec: 'Chrome • Firefox • Safari',
                  description:
                      'Zero-install interactive browser preview. Test playlist imports and browse the curated library directly in your browser.',
                  buttonText: 'Open Web Player',
                  isPrimary: false,
                  onTap: () => _launchWebPlayer(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPlatformCard({
    required double width,
    required IconData icon,
    required String title,
    required String badge,
    required String spec,
    required String description,
    required String buttonText,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121215),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C20),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF2E2E33)),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec,
            style: const TextStyle(
              color: Color(0xFF71717A),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFA1A1AA),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: isPrimary
                ? ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 0,
                    ),
                    child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  )
                : OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3F3F46)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
          ),
        ],
      ),
    );
  }

  // MARK: - Architectural Features
  Widget _buildFeaturesSection(bool isDesktop) {
    final features = [
      (
        num: '01',
        title: 'Native Client Resolution',
        desc:
            'Audio streams are resolved locally on the user device via decentralized scraping. No central proxy hosts copyrighted files.',
      ),
      (
        num: '02',
        title: 'Offline-First Architecture',
        desc:
            'Download tracks directly to your local file system. Enjoy your music collection completely offline with zero buffer interruptions.',
      ),
      (
        num: '03',
        title: 'Tri-Platform Importer',
        desc:
            'Seamlessly migrate your favorite playlists from Spotify, YouTube, and Apple Music using raw embed metadata scraping.',
      ),
      (
        num: '04',
        title: 'Architectural Minimalism',
        desc:
            'Engineered in pure obsidian black (#0A0A0A) with crisp geometric soundwave typography. Zero ads, trackers, or AI noise.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CORE CAPABILITIES',
          style: TextStyle(
            color: Color(0xFFA1A1AA),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final colWidth = isDesktop ? (constraints.maxWidth - 24) / 2 : constraints.maxWidth;

            return Wrap(
              spacing: 24,
              runSpacing: 20,
              children: features.map((f) {
                return Container(
                  width: colWidth,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF222226)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.num,
                        style: const TextStyle(
                          color: Color(0xFF52525B),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              f.desc,
                              style: const TextStyle(
                                color: Color(0xFFA1A1AA),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // MARK: - Footer
  Widget _buildFooter(BuildContext context, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1E1E22), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const SymphonyBrandLogo(size: 20),
              const SizedBox(width: 8),
              const Text(
                'SYMPHONY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _openExternal(portfolioUrl),
                child: const Text(
                  'by jettimothycerezo.dev',
                  style: TextStyle(
                    color: Color(0xFF71717A),
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _openExternal(repoUrl),
                icon: const Icon(Icons.code_rounded, size: 16, color: Color(0xFFA1A1AA)),
                tooltip: 'Source Code',
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => _launchWebPlayer(context),
                child: const Text(
                  'Launch Web Demo',
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
