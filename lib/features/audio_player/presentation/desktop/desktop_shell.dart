import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/realtime_download_toast.dart';
import '../widgets/sidebar_nav.dart';

/// Wide-window chrome: sidebar navigation, rounded content panel and the
/// full-width player bar. [content] is the active tab's view.
class DesktopShell extends ConsumerWidget {
  final Widget content;

  const DesktopShell({super.key, required this.content});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
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
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        const SidebarNav(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
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
