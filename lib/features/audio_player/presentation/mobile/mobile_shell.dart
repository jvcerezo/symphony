import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/navigation_history_provider.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/realtime_download_toast.dart';

/// Narrow-window chrome: edge-to-edge content panel, floating player bar and
/// bottom navigation (Home / Search / Your Library). [content] is the active
/// tab's view.
class MobileShell extends ConsumerWidget {
  final String activeTab;
  final Widget content;

  const MobileShell({super.key, required this.activeTab, required this.content});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: activeTab == 'home'
            ? 0
            : activeTab == 'search'
                ? 1
                : 2,
        onTap: (idx) {
          final tab = idx == 0
              ? 'home'
              : idx == 1
                  ? 'search'
                  : 'library';
          if (tab == 'home') {
            ref.read(activePlaylistProvider.notifier).state = null;
          }
          ref.read(activeNavTabProvider.notifier).state = tab;
          ref.read(navigationHistoryProvider.notifier).record(tab, tab == 'home' ? null : ref.read(activePlaylistProvider));
        },
        backgroundColor: SymphonyTheme.obsidian,
        selectedItemColor: Colors.white,
        unselectedItemColor: SymphonyTheme.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Your Library'),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppUpdateBanner(
              onDismiss: () => ref.read(appUpdateProvider.notifier).markUserNotified(),
            ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.zero,
                            child: Container(
                              color: SymphonyTheme.panel,
                              child: content,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Real-time live download toast overlay
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: const RealtimeDownloadToast(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const BottomPlayerBar(),
          ],
        ),
      ),
    );
  }
}
