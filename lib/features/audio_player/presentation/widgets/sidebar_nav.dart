import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../controllers/audio_player_providers.dart';
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
                // Symphony Brand Header
                Padding(
                  padding: const EdgeInsets.only(left: 6.0, top: 4.0, bottom: 16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: accent.gradient,
                          boxShadow: [
                            BoxShadow(
                              color: accent.primary.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Colors.black, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'SYMPHONY',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // Nav item: Home
                _buildNavItem(
                  icon: activeTab == 'home' ? Icons.home_filled : Icons.home_outlined,
                  label: 'Home',
                  isSelected: activeTab == 'home',
                  onTap: () => ref.read(activeNavTabProvider.notifier).state = 'home',
                ),

                const SizedBox(height: 4),

                // Nav item: Search
                _buildNavItem(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  isSelected: activeTab == 'search',
                  onTap: () => ref.read(activeNavTabProvider.notifier).state = 'search',
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
                        InkWell(
                          onTap: () => ref.read(activeNavTabProvider.notifier).state = 'library',
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            children: [
                              Icon(
                                activeTab == 'library' ? Icons.library_music : Icons.library_music_outlined,
                                color: activeTab == 'library' ? Colors.white : SymphonyTheme.textSecondary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Your Library',
                                style: TextStyle(
                                  color: activeTab == 'library' ? Colors.white : SymphonyTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
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
                    child: Row(
                      children: [
                        _buildFilterChip('Playlists', 'all', accent),
                        const SizedBox(width: 8),
                        _buildFilterChip('Downloaded', 'downloaded', accent, icon: Icons.download_done_rounded),
                      ],
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

class _SidebarPlaylistItem extends StatefulWidget {
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
  State<_SidebarPlaylistItem> createState() => _SidebarPlaylistItemState();
}

class _SidebarPlaylistItemState extends State<_SidebarPlaylistItem> {
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
