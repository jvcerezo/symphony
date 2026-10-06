import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../../../../core/widgets/symphony_brand_logo.dart';
import '../../../settings/presentation/controllers/personalization_provider.dart';
import '../../../settings/presentation/widgets/personalization_dialog.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/navigation_history_provider.dart';
import '../controllers/offline_provider.dart';
import 'import_playlist_dialog.dart';

class SidebarNav extends ConsumerStatefulWidget {
  const SidebarNav({super.key});

  @override
  ConsumerState<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends ConsumerState<SidebarNav> {
  String _selectedFilter = 'all'; // 'all' | 'downloaded'
  String _librarySearch = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final activeTab = ref.watch(activeNavTabProvider);
    final currentMediaItem = ref.watch(currentMediaItemStreamProvider).asData?.value;
    final playbackState = ref.watch(playbackStateStreamProvider).asData?.value;
    final isPlaying = playbackState?.playing ?? false;
    final offlineState = ref.watch(offlineProvider);
    final accent = ref.watch(accentThemeProvider);
    final personalization = ref.watch(personalizationProvider);
    final updateState = ref.watch(appUpdateProvider);

    // Filter playlists
    var filteredPlaylists = importedPlaylists;
    if (_selectedFilter == 'downloaded') {
      filteredPlaylists = filteredPlaylists.where((p) => offlineState.isPlaylistDownloaded(p)).toList();
    }
    if (_librarySearch.trim().isNotEmpty) {
      final q = _librarySearch.toLowerCase();
      filteredPlaylists = filteredPlaylists.where((p) =>
        p.title.toLowerCase().contains(q) ||
        (p.ownerName ?? '').toLowerCase().contains(q)
      ).toList();
    }

    return SizedBox(
      width: 280,
      child: Column(
        children: [
          // 1. Top Card: Brand & Primary Navigation
          Container(
            decoration: BoxDecoration(
              color: SymphonyTheme.panel,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Symphony Personalized Brand Header with Official Logo
                Padding(
                  padding: const EdgeInsets.only(left: 2.0, top: 4.0, bottom: 16.0),
                  child: SymphonyBrandHeader(
                    title: personalization.displayTitle,
                    subtitle: personalization.userName.isNotEmpty
                        ? personalization.userName
                        : 'Offline Music Engine',
                    accent: accent,
                    trailing: updateState.hasUpdate && updateState.latestRelease != null
                        ? InkWell(
                            onTap: () => AppUpdateDialog.show(context, updateState.latestRelease!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'UPDATE',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => const PersonalizationDialog(),
                      );
                    },
                  ),
                ),

                // Nav item: Home
                _buildNavItem(
                  icon: (activeTab == 'home' && activePlaylist == null) ? Icons.home_filled : Icons.home_outlined,
                  label: 'Home',
                  isSelected: activeTab == 'home' && activePlaylist == null,
                  onTap: () {
                    ref.read(activePlaylistProvider.notifier).state = null;
                    ref.read(activeNavTabProvider.notifier).state = 'home';
                    ref.read(navigationHistoryProvider.notifier).record('home', null);
                  },
                ),

                const SizedBox(height: 4),

                // Nav item: Search
                _buildNavItem(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  isSelected: activeTab == 'search',
                  onTap: () {
                    ref.read(activeNavTabProvider.notifier).state = 'search';
                    ref.read(navigationHistoryProvider.notifier).record('search', null);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 2. Bottom Card: Your Library (Spotify Layout)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: SymphonyTheme.panel,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Library Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              ref.read(activeNavTabProvider.notifier).state = 'library';
                              ref.read(navigationHistoryProvider.notifier).record('library', null);
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              children: [
                                Icon(
                                  activeTab == 'library' ? Icons.library_music : Icons.library_music_outlined,
                                  color: activeTab == 'library' ? Colors.white : SymphonyTheme.textSecondary,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    'Your Library',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: activeTab == 'library' ? Colors.white : SymphonyTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.add, color: SymphonyTheme.textSecondary, size: 22),
                          tooltip: 'Import or Create Playlist',
                          hoverColor: SymphonyTheme.cardHover,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => const ImportPlaylistDialog(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Filter Chips (Pills)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('Playlists', 'all', accent),
                          const SizedBox(width: 8),
                          _buildFilterChip('Downloaded', 'downloaded', accent, icon: Icons.download_done_rounded),
                        ],
                      ),
                    ),
                  ),

                  // Search in Library Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        if (_isSearching)
                          Expanded(
                            child: SizedBox(
                              height: 32,
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Search in Your Library',
                                  hintStyle: const TextStyle(fontSize: 12, color: SymphonyTheme.textMuted),
                                  filled: true,
                                  fillColor: SymphonyTheme.cardHover,
                                  prefixIcon: const Icon(Icons.search, size: 16, color: SymphonyTheme.textMuted),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.close, size: 14, color: SymphonyTheme.textMuted),
                                    onPressed: () {
                                      setState(() {
                                        _librarySearch = '';
                                        _searchController.clear();
                                        _isSearching = false;
                                      });
                                    },
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (val) => setState(() => _librarySearch = val),
                              ),
                            ),
                          )
                        else ...[
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            icon: const Icon(Icons.search, color: SymphonyTheme.textSecondary),
                            tooltip: 'Search in Your Library',
                            onPressed: () => setState(() => _isSearching = true),
                          ),
                          const Spacer(),
                          const Text(
                            'Recents',
                            style: TextStyle(fontSize: 12, color: SymphonyTheme.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.sort, size: 16, color: SymphonyTheme.textSecondary),
                        ],
                      ],
                    ),
                  ),

                  // Playlists List
                  Expanded(
                    child: filteredPlaylists.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text(
                                _selectedFilter == 'downloaded'
                                    ? 'No downloaded playlists yet'
                                    : 'No playlists found',
                                style: const TextStyle(color: SymphonyTheme.textMuted, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            itemCount: filteredPlaylists.length,
                            itemBuilder: (context, index) {
                              final playlist = filteredPlaylists[index];
                              final isSelected = activePlaylist?.id == playlist.id && activeTab == 'home';
                              final isThisPlaylistPlaying = isPlaying &&
                                  playlist.tracks.any((t) => t.title == currentMediaItem?.title && t.artist == currentMediaItem?.artist);
                              final isDownloaded = offlineState.isPlaylistDownloaded(playlist);

                              return _SidebarPlaylistItem(
                                playlist: playlist,
                                isSelected: isSelected,
                                isPlaying: isThisPlaylistPlaying,
                                isDownloaded: isDownloaded,
                                accent: accent,
                                onTap: () {
                                  ref.read(activePlaylistProvider.notifier).state = playlist;
                                  ref.read(activeNavTabProvider.notifier).state = 'home';
                                  ref.read(navigationHistoryProvider.notifier).record('home', playlist);
                                },
                              );
                            },
                          ),
                  ),

                  // Symphony Theme Accent Picker
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFF242424), width: 1)),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'ACCENT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: SymphonyTheme.textMuted,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: SymphonyTheme.accents.map((acc) {
                            final isCurrent = acc.name == accent.name;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Tooltip(
                                message: acc.name,
                                child: InkWell(
                                  onTap: () => ref.read(accentThemeProvider.notifier).state = acc,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: isCurrent ? 16 : 12,
                                    height: isCurrent ? 16 : 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: acc.primary,
                                      border: isCurrent
                                          ? Border.all(color: Colors.white, width: 2)
                                          : null,
                                      boxShadow: isCurrent
                                          ? [
                                              BoxShadow(
                                                color: acc.primary.withOpacity(0.6),
                                                blurRadius: 6,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      hoverColor: SymphonyTheme.cardHover.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : SymphonyTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : SymphonyTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, SymphonyAccent accent, {IconData? icon}) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = isSelected && value != 'all' ? 'all' : value;
        });
      },
      borderRadius: BorderRadius.circular(500),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : SymphonyTheme.cardHover,
          borderRadius: BorderRadius.circular(500),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? Colors.black : accent.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarPlaylistItem extends ConsumerStatefulWidget {
  final dynamic playlist;
  final bool isSelected;
  final bool isPlaying;
  final bool isDownloaded;
  final SymphonyAccent accent;
  final VoidCallback onTap;

  const _SidebarPlaylistItem({
    required this.playlist,
    required this.isSelected,
    required this.isPlaying,
    required this.isDownloaded,
    required this.accent,
    required this.onTap,
  });

  @override
  ConsumerState<_SidebarPlaylistItem> createState() => _SidebarPlaylistItemState();
}

class _SidebarPlaylistItemState extends ConsumerState<_SidebarPlaylistItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? SymphonyTheme.cardHover
                : (_isHovered ? SymphonyTheme.cardHover.withOpacity(0.5) : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: playlist.coverUrl != null
                    ? Image.network(
                        playlist.coverUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildFallbackCover(),
                      )
                    : _buildFallbackCover(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.title,
                      style: TextStyle(
                        color: widget.isPlaying
                            ? widget.accent.primary
                            : (widget.isSelected ? Colors.white : Colors.white),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (widget.isDownloaded) ...[
                          Icon(Icons.download_done_rounded, size: 13, color: widget.accent.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            'Playlist • ${playlist.ownerName ?? "Symphony"}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SymphonyTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.isPlaying)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(Icons.volume_up_rounded, color: widget.accent.primary, size: 16),
                ),
              // 3-dots popup menu for playlist download & play choices
              PopupMenuButton<String>(
                icon: Icon(
                  widget.isDownloaded
                      ? Icons.check_circle_rounded
                      : Icons.more_vert_rounded,
                  color: widget.isDownloaded
                      ? widget.accent.primary
                      : (_isHovered ? Colors.white70 : Colors.transparent),
                  size: 16,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: const Color(0xFF242424),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tooltip: 'Playlist options',
                onSelected: (val) async {
                  if (val == 'download') {
                    ref.read(offlineProvider.notifier).downloadPlaylist(playlist);
                  } else if (val == 'play') {
                    ref.read(activePlaylistProvider.notifier).state = playlist;
                    ref.read(audioHandlerProvider).playQueue(playlist.tracks, startIndex: 0);
                  } else if (val == 'uninstall_download') {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF242424),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: const Text('Uninstall Offline Download?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text(
                          'This will remove all downloaded audio files for "${playlist.title}" from your device to free up storage space. The playlist will remain in your library for online streaming.',
                          style: const TextStyle(color: SymphonyTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final freed = await ref.read(offlineProvider.notifier).removeDownloadedPlaylist(playlist);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF282828),
                                    content: Text('Uninstalled offline songs for "${playlist.title}" (${freed ?? "freed cache"})'),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                            child: const Text('Uninstall', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  } else if (val == 'delete_playlist') {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF242424),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text(
                          'Are you sure you want to remove "${playlist.title}" from your library? Any downloaded audio files will also be cleanly uninstalled.',
                          style: const TextStyle(color: SymphonyTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await ref.read(offlineProvider.notifier).removeDownloadedPlaylist(playlist);
                              ref.read(importedPlaylistsProvider.notifier).removePlaylist(playlist.id);
                              if (ref.read(activePlaylistProvider)?.id == playlist.id) {
                                final remaining = ref.read(importedPlaylistsProvider);
                                ref.read(activePlaylistProvider.notifier).state = remaining.isNotEmpty ? remaining.first : null;
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF282828),
                                    content: Text('Removed "${playlist.title}" from library'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(
                          widget.isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                          color: widget.isDownloaded ? widget.accent.primary : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.isDownloaded ? 'Downloaded (Redownload)' : 'Download Playlist Offline',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'play',
                    child: Row(
                      children: const [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 10),
                        Text('Play Playlist', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (widget.isDownloaded)
                    PopupMenuItem(
                      value: 'uninstall_download',
                      child: Row(
                        children: const [
                          Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 18),
                          SizedBox(width: 10),
                          Text('Uninstall Offline Download', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete_playlist',
                    child: Row(
                      children: const [
                        Icon(Icons.delete_outline_rounded, color: SymphonyTheme.textSecondary, size: 18),
                        SizedBox(width: 10),
                        Text('Delete from Library', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
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

  Widget _buildFallbackCover() {
    return Container(
      width: 48,
      height: 48,
      color: SymphonyTheme.cardHover,
      child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted, size: 22),
    );
  }
}
