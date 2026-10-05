import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../controllers/audio_player_providers.dart';
import 'import_playlist_dialog.dart';

class SidebarNav extends ConsumerWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final activeTab = ref.watch(activeNavTabProvider);

    return Container(
      width: 250,
      color: SymphonyTheme.obsidian,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Symphony Brand Header
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 24.0),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: SymphonyTheme.brandGradient,
                  ),
                  child: const Icon(Icons.graphic_eq, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'SYMPHONY',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Primary Navigation Links
          _buildNavItem(
            icon: Icons.home_filled,
            label: 'Home',
            isSelected: activeTab == 'home',
            onTap: () => ref.read(activeNavTabProvider.notifier).state = 'home',
          ),
          _buildNavItem(
            icon: Icons.search,
            label: 'Search',
            isSelected: activeTab == 'search',
            onTap: () => ref.read(activeNavTabProvider.notifier).state = 'search',
          ),
          _buildNavItem(
            icon: Icons.library_music,
            label: 'Your Library',
            isSelected: activeTab == 'library',
            onTap: () => ref.read(activeNavTabProvider.notifier).state = 'library',
          ),

          const SizedBox(height: 16),

          // Import Spotify Button
          ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const ImportPlaylistDialog(),
              );
            },
            icon: const Icon(Icons.add_circle, color: SymphonyTheme.secondary, size: 18),
            label: const Text(
              'Import Spotify',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: SymphonyTheme.card,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: SymphonyTheme.divider),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: SymphonyTheme.divider, height: 1),
          const SizedBox(height: 16),

          // Playlists Header
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              'IMPORTED PLAYLISTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: SymphonyTheme.textMuted,
              ),
            ),
          ),

          // Playlists List
          Expanded(
            child: ListView.builder(
              itemCount: importedPlaylists.length,
              itemBuilder: (context, index) {
                final playlist = importedPlaylists[index];
                final isSelected = activePlaylist?.id == playlist.id;

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    playlist.title,
                    style: TextStyle(
                      color: isSelected ? SymphonyTheme.primaryLight : SymphonyTheme.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${playlist.trackCount} tracks',
                    style: const TextStyle(fontSize: 11, color: SymphonyTheme.textMuted),
                  ),
                  onTap: () {
                    ref.read(activePlaylistProvider.notifier).state = playlist;
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      leading: Icon(
        icon,
        color: isSelected ? SymphonyTheme.primaryLight : SymphonyTheme.textSecondary,
        size: 24,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : SymphonyTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      onTap: onTap,
    );
  }
}
