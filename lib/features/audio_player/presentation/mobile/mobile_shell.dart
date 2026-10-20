import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../browse/presentation/genre_providers.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/navigation_history_provider.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/realtime_download_toast.dart';

/// Narrow-window chrome: edge-to-edge content panel with the floating player
/// bar and bottom navigation (Home / Search / Your Library) on a near-black bar
/// over it. [content] is the active tab's view; its scroll views pad their
/// end by `MediaQuery.paddingOf(context).bottom` to clear the bar.
class MobileShell extends ConsumerWidget {
  final String activeTab;
  final Widget content;

  const MobileShell({super.key, required this.activeTab, required this.content});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
      // The body runs under the bar; Scaffold adds its height to the
      // body's bottom padding.
      extendBody: true,
      // Near-solid, not frosted: a live blur here would be redone every frame
      // anything under it moves, which kept the GPU busy while music played.
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SymphonyTheme.navBar, SymphonyTheme.obsidian],
            stops: [0.0, 0.9],
          ),
          border: Border(top: BorderSide(color: SymphonyTheme.glassEdge, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: BottomPlayerBar(),
            ),
            BottomNavigationBar(
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
                  ref.read(activeGenreProvider.notifier).state = null;
                }
                ref.read(activeNavTabProvider.notifier).state = tab;
                ref.read(navigationHistoryProvider.notifier).record(tab, tab == 'home' ? null : ref.read(activePlaylistProvider));
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.white,
              unselectedItemColor: SymphonyTheme.textSecondary,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Your Library'),
              ],
            ),
          ],
        ),
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
                  Positioned.fill(
                    child: Container(
                      color: SymphonyTheme.panel,
                      child: content,
                    ),
                  ),
                  // Real-time live download toast overlay, above the bar.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8 + MediaQuery.paddingOf(context).bottom,
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
          ],
        ),
      ),
    );
  }
}
