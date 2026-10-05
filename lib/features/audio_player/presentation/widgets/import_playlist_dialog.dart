import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../controllers/audio_player_providers.dart';

class ImportPlaylistDialog extends ConsumerStatefulWidget {
  const ImportPlaylistDialog({super.key});

  @override
  ConsumerState<ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends ConsumerState<ImportPlaylistDialog> {
  final _inputController = TextEditingController(
    text: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
  );
  String _selectedCategory = 'All';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleImport() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final importer = ref.read(universalPlaylistImporterProvider);
      final playlist = await importer.importPlaylist(input);

      // Save to state
      ref.read(importedPlaylistsProvider.notifier).addPlaylist(playlist);
      ref.read(activePlaylistProvider.notifier).state = playlist;

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SymphonyTheme.card,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: SymphonyTheme.primaryLight, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Imported "${playlist.title}" from ${playlist.source} (${playlist.trackCount} tracks)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('FormatException: ', '').replaceFirst('AudioStreamResolutionException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentThemeProvider);

    return Dialog(
      backgroundColor: const Color(0xFF282828),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add_to_photos_rounded, color: accent.primary, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Import Playlist',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Spotify • YouTube • Apple Music • Deezer • Smart Mix',
                          style: TextStyle(fontSize: 12, color: SymphonyTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: SymphonyTheme.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Source Filter Chips
              Wrap(
                spacing: 8,
                children: ['All', 'Spotify', 'YouTube', 'Apple Music', 'Deezer', 'Smart Mix'].map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.black : Colors.white,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.white,
                    backgroundColor: const Color(0xFF3E3E3E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                    side: BorderSide.none,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              const Text(
                'Playlist Link or Artist Name',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SymphonyTheme.textSecondary),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _inputController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Paste Spotify, YouTube, Apple Music, Deezer URL or type artist...',
                  hintStyle: const TextStyle(color: SymphonyTheme.textMuted),
                  filled: true,
                  fillColor: const Color(0xFF3E3E3E),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: accent.primary, width: 1.5),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],

              const SizedBox(height: 16),
              const Text(
                'Featured Presets:',
                style: TextStyle(fontSize: 12, color: SymphonyTheme.textMuted),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _getFilteredPresets().map((p) => _buildPresetChip(p.name, p.url, p.source, accent)).toList(),
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: SymphonyTheme.textSecondary, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleImport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent.primary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          )
                        : const Text('Import & Play Ad-Free', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),

              // Open-Source Independent Client Disclaimer
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: SymphonyTheme.textMuted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Symphony is an independent open-source music player not affiliated with, endorsed by, or sponsored by Spotify AB or any streaming platform.',
                        style: TextStyle(fontSize: 11, color: SymphonyTheme.textMuted, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<({String name, String url, String source})> _getFilteredPresets() {
    final all = [
      (name: "Spotify: Today's Top Hits", url: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M', source: 'Spotify'),
      (name: "Spotify: Mega Hit Mix", url: 'https://open.spotify.com/playlist/37i9dQZF1DXbYM3nMM0oPk', source: 'Spotify'),
      (name: 'Deezer: En Mode 60 Hits', url: 'https://www.deezer.com/playlist/908622995', source: 'Deezer'),
      (name: 'Apple Music: Top 50 Chart', url: 'https://itunes.apple.com/us/rss/topsongs/limit=50/json', source: 'Apple Music'),
      (name: 'YouTube: Hits Playlist', url: 'https://www.youtube.com/playlist?list=PL4fGSIFgk5n0vF4P4V3d9_aF80hD_lD7w', source: 'YouTube'),
      (name: 'Smart Mix: Taylor Swift', url: 'Taylor Swift', source: 'Smart Mix'),
      (name: 'Smart Mix: Chill Synthwave', url: 'Synthwave', source: 'Smart Mix'),
    ];

    if (_selectedCategory == 'All') return all;
    return all.where((p) => p.source == _selectedCategory).toList();
  }

  Widget _buildPresetChip(String label, String url, String source, SymphonyAccent accent) {
    return ActionChip(
      avatar: Icon(
        source == 'Spotify'
            ? Icons.graphic_eq
            : source == 'YouTube'
                ? Icons.play_circle_fill
                : source == 'Deezer'
                    ? Icons.waves
                    : source == 'Apple Music'
                        ? Icons.music_note
                        : Icons.auto_awesome,
        size: 16,
        color: accent.primary,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: const Color(0xFF333333),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
      side: BorderSide.none,
      onPressed: () {
        _inputController.text = url;
      },
    );
  }
}
