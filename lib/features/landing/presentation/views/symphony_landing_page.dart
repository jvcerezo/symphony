import '../../../../core/config/feature_flags.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/widgets/symphony_brand_logo.dart';
import '../../../audio_player/presentation/views/symphony_player_screen.dart';
import '../../../audio_player/presentation/widgets/animated_equalizer.dart';
import '../../../jam/domain/jam_invite.dart';
import '../widgets/jam_invite_card.dart';
import '../widgets/wave_background.dart';

/// The official public showcase & distribution landing page for Symphony.
/// Designed with an architectural, monochrome aesthetic (consistent with jettimothycerezo.dev).
class SymphonyLandingPage extends ConsumerWidget {
  const SymphonyLandingPage({super.key});

  static const String repoUrl = 'https://github.com/jvcerezo/symphony';
  static const String portfolioUrl = 'https://jettimothycerezo.dev';
  static const String fallbackWindowsUrl =
      'https://github.com/jvcerezo/symphony/releases/download/latest/symphony-windows-x64.zip';
  static const String fallbackAndroidUrl =
      'https://github.com/jvcerezo/symphony/releases/download/latest/symphony.apk';
  static const String fallbackMacUrl =
      'https://github.com/jvcerezo/symphony/releases/download/latest/symphony-macos.zip';
  static const String fallbackIosUrl =
      'https://github.com/jvcerezo/symphony/releases/download/latest/symphony-ios.ipa';
  static const String discordInviteUrl =
      'https://discord.com/oauth2/authorize?client_id=1559096164345970708&scope=bot&permissions=3230720';
  static const String termsUrl = '/terms-of-service';
  static const String privacyUrl = '/privacy-policy';

  static void _openExternal(String url, {bool isDownload = false}) {
    AppUpdateNotifier.openUrl(url, isDownload: isDownload);
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
    // Releases are tagged "latest"; the version lives in the title ("Symphony v1.0.42").
    final titleVersion = RegExp(r'v\d+\.\d+(?:\.\d+)?').firstMatch(latestRelease?.title ?? '')?.group(0);
    final versionTag = titleVersion ?? latestRelease?.tagName ?? 'latest';
    final hasDirectWindowsAsset =
        latestRelease?.windowsDownloadUrl != null || fallbackWindowsUrl.endsWith('.zip');
    final winDownloadUrl = latestRelease?.windowsDownloadUrl ?? fallbackWindowsUrl;
    final apkDownloadUrl = latestRelease?.androidDownloadUrl ?? fallbackAndroidUrl;
    final macDownloadUrl = latestRelease?.macDownloadUrl ?? fallbackMacUrl;
    final iosDownloadUrl = latestRelease?.iosDownloadUrl ?? fallbackIosUrl;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 860;
    // Opened from a Jam invite link.
    final inviteCode = JamInvite.codeFrom(Uri.base);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // 0. Architectural Generative Wave Background Animation
          const Positioned.fill(
            child: IgnorePointer(
              child: WaveBackground(),
            ),
          ),

          // 1. Interactive Page Showcase Content
          SafeArea(
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

                        if (inviteCode != null) ...[
                          SizedBox(height: isDesktop ? 40 : 24),
                          JamInviteCard(
                            code: inviteCode,
                            onDownload: () => defaultTargetPlatform == TargetPlatform.android
                                ? _openExternal(apkDownloadUrl, isDownload: true)
                                : _openExternal(hasDirectWindowsAsset ? winDownloadUrl : repoUrl,
                                    isDownload: hasDirectWindowsAsset),
                          ),
                        ],

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
                          macDownloadUrl,
                          iosDownloadUrl,
                          versionTag,
                        ),

                        SizedBox(height: isDesktop ? 80 : 56),

                        // 4. The Discord bot
                        _buildDiscordSection(isDesktop),

                        SizedBox(height: isDesktop ? 80 : 56),

                        // 5. Architectural Features Breakdown
                        _buildFeaturesSection(isDesktop),

                        SizedBox(height: isDesktop ? 80 : 56),

                        // 6. Minimalist Portfolio Footer
                        _buildFooter(context, isDesktop),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
            const SymphonyBrandLogo(size: 32, animated: false),
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
            if (FeatureFlags.webDemoEnabled)
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
        // Tagline Pill with Live Soundwave
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedEqualizer(isPlaying: false, height: 11, color: Colors.white),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                'OFFLINE-FIRST • PRIVATE • ZERO ADS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              ),
            ],
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
            'Save any song or playlist to your device and play it anywhere, even with no connection.',
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
              onPressed: () => _openExternal(winDownloadUrl, isDownload: true),
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
              onPressed: () => _openExternal(apkDownloadUrl, isDownload: true),
              icon: const Icon(Icons.android_rounded, size: 18, color: Colors.white),
              label: const Text('Download Android APK', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3F3F46)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (FeatureFlags.webDemoEnabled)
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

        const SizedBox(height: 18),

        // Personal note: the Windows build isn't code-signed, so SmartScreen warns.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFFA1A1AA)),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: "Ako nag-dev nito — trust me, it's safe.\n",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: "Windows may flag it because the app isn't code-signed. "
                            'Click More info → Run anyway.',
                      ),
                    ],
                  ),
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13, height: 1.6),
                ),
              ),
            ],
          ),
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
    String macDownloadUrl,
    String iosDownloadUrl,
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
            const columns = 2;
            final cardWidth = isDesktop ? (constraints.maxWidth - 16 * (columns - 1)) / columns : constraints.maxWidth;

            final cards = <Widget>[
                // 1. Windows Desktop Card
                _buildPlatformCard(
                  width: cardWidth,
                  fillHeight: isDesktop,
                  icon: Icons.desktop_windows_rounded,
                  title: 'Windows Desktop',
                  badge: hasDirectWindowsAsset ? 'Portable .zip' : 'GitHub Releases',
                  spec: 'Windows 10 / 11 • 64-bit',
                  description:
                      'Hardware media keys, system tray, keyboard shortcuts, and unlimited offline downloads.',
                  buttonText: hasDirectWindowsAsset ? 'Download .zip' : 'View on GitHub',
                  isPrimary: true,
                  onTap: () => _openExternal(winDownloadUrl, isDownload: true),
                ),

                // 2. Android Mobile Card
                _buildPlatformCard(
                  width: cardWidth,
                  fillHeight: isDesktop,
                  icon: Icons.android_rounded,
                  title: 'Android Mobile',
                  badge: 'Native APK',
                  spec: 'Android 8.0+ (Oreo+)',
                  description:
                      'Lockscreen media session, background playback service, offline track management, and touch-optimized navigation.\n\n'
                      // Builds before 2026-10-17 were signed with a key that changed every build.
                      'Installed Symphony before October 17, 2026? If Android says the package conflicts, uninstall Symphony once and install this. Updates after that install normally.',
                  buttonText: 'Download .apk',
                  isPrimary: false,
                  onTap: () => _openExternal(apkDownloadUrl, isDownload: true),
                ),

                // 3. macOS Card
                _buildPlatformCard(
                  width: cardWidth,
                  fillHeight: isDesktop,
                  icon: Icons.laptop_mac_rounded,
                  title: 'macOS',
                  badge: 'Universal .zip',
                  spec: 'macOS 10.15+ • Apple silicon & Intel',
                  description:
                      'The first time, right-click Symphony and choose Open: the app is not notarized by Apple. '
                      'It sets up its audio tools on first start.',
                  buttonText: 'Download .zip',
                  isPrimary: false,
                  onTap: () => _openExternal(macDownloadUrl, isDownload: true),
                ),

                // 4. iPhone / iPad Card
                _buildPlatformCard(
                  width: cardWidth,
                  fillHeight: isDesktop,
                  icon: Icons.phone_iphone_rounded,
                  title: 'iPhone & iPad',
                  badge: 'Sideload .ipa',
                  spec: 'iOS 13+ • install with Sideloadly',
                  description:
                      'Install from your computer with Sideloadly and a free Apple ID; re-install every 7 days. '
                      'Early version: some songs may not play yet.',
                  buttonText: 'Download .ipa',
                  isPrimary: false,
                  onTap: () => _openExternal(iosDownloadUrl, isDownload: true),
                ),

                // 5. Web Player Card (needs a live server.dart backend)
                if (FeatureFlags.webDemoEnabled)
                  _buildPlatformCard(
                  width: cardWidth,
                  fillHeight: isDesktop,
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
            ];

            if (!isDesktop) {
              return Wrap(spacing: 16, runSpacing: 16, children: cards);
            }
            // Rows of equal-height cards, so the buttons line up whatever the
            // length of each description.
            return Column(
              children: [
                for (var i = 0; i < cards.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = i; j < i + columns; j++) ...[
                          if (j > i) const SizedBox(width: 16),
                          Expanded(child: j < cards.length ? cards[j] : const SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                ],
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
    bool fillHeight = false,
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
          // Push the button to the bottom when the card is stretched to its row.
          if (fillHeight) const Spacer(),
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

  // MARK: - Discord Bot
  Widget _buildDiscordSection(bool isDesktop) {
    const steps = [
      (num: '1', title: 'Add it to your server', desc: 'Click "Add to Discord" and pick a server you manage.'),
      (num: '2', title: 'Join a voice channel', desc: 'The bot joins the channel you are in.'),
      (num: '3', title: 'Type s!play', desc: 'A song name, or a link to a song or playlist.'),
    ];

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.discord, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Symphony for Discord',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Listen together. The Symphony bot plays music in your voice channel for everyone in it, '
          'with a shared queue, skip and pause buttons, shuffle and repeat.',
          style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => _openExternal(discordInviteUrl),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add to Discord'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Needs "Manage Server" permission in that server. The bot is a personal project, '
          'so it may be offline at times.',
          style: TextStyle(color: Color(0xFF71717A), fontSize: 12, height: 1.5),
        ),
      ],
    );

    final stepList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E22),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFF2E2E33)),
                  ),
                  child: Text(
                    step.num,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        step.desc,
                        style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISCORD BOT',
          style: TextStyle(
            color: Color(0xFFA1A1AA),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isDesktop ? 32 : 24),
          decoration: BoxDecoration(
            color: const Color(0xFF121215),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 48),
                    Expanded(child: stepList),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [intro, const SizedBox(height: 28), stepList],
                ),
        ),
      ],
    );
  }

  // MARK: - Architectural Features
  Widget _buildFeaturesSection(bool isDesktop) {
    final features = [
      (
        num: '01',
        title: 'No Account, No Server',
        desc:
            'Everything runs on your own device. Nothing to sign up for, and your library and history never leave it.',
      ),
      (
        num: '02',
        title: 'Offline-First Architecture',
        desc:
            'Download tracks directly to your local file system. Enjoy your music collection completely offline with zero buffer interruptions.',
      ),
      (
        num: '03',
        title: 'Bring Your Playlists',
        desc:
            'Paste a playlist link from the app you use today and Symphony rebuilds it, or search any song by name.',
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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 0,
            runSpacing: 4,
            children: [
              const SymphonyBrandLogo(size: 20, animated: false),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _openExternal(termsUrl),
                child: const Text('Terms', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _openExternal(privacyUrl),
                child: const Text('Privacy', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
              ),
              IconButton(
                onPressed: () => _openExternal(repoUrl),
                icon: const Icon(Icons.code_rounded, size: 16, color: Color(0xFFA1A1AA)),
                tooltip: 'Source Code',
              ),
              if (FeatureFlags.webDemoEnabled) const SizedBox(width: 4),
              if (FeatureFlags.webDemoEnabled)
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
