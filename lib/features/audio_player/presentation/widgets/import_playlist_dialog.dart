import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../settings/presentation/controllers/personalization_provider.dart';
import '../controllers/audio_player_providers.dart';

class ImportPlaylistDialog extends ConsumerStatefulWidget {
  const ImportPlaylistDialog({super.key});

  @override
  ConsumerState<ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends ConsumerState<ImportPlaylistDialog> {
  String _selectedPlatform = 'Spotify'; // 'Spotify' | 'YouTube' | 'Apple Music'
  late final TextEditingController _inputController;
  bool _isLoading = false;
  String? _errorMessage;

  static const Map<String, String> _defaultUrls = {
    'Spotify': 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
    'YouTube': 'https://www.youtube.com/playlist?list=PL4fGSIFgk5n0vF4P4V3d9_aF80hD_lD7w',
    'Apple Music': 'https://itunes.apple.com/us/rss/topsongs/limit=50/json',
  };

  static const Map<String, String> _placeholders = {
    'Spotify': 'https://open.spotify.com/playlist/37i9dQZF1DX... or playlist ID',
    'YouTube': 'https://www.youtube.com/playlist?list=PL4fGSIFg...',
    'Apple Music': 'https://music.apple.com/... or iTunes chart URL',
  };

  static const Map<String, String> _inputLabels = {
    'Spotify': 'Spotify Playlist URL or ID',
    'YouTube': 'YouTube Playlist Link',
    'Apple Music': 'Apple Music or iTunes Link',
  };

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: _defaultUrls['Spotify']);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _onSelectPlatform(String platform) {
    if (_selectedPlatform == platform) return;
    final currentText = _inputController.text.trim();
    final wasTemplate = _defaultUrls.values.contains(currentText) || currentText.isEmpty;

    setState(() {
      _selectedPlatform = platform;
      if (wasTemplate) {
        _inputController.text = _defaultUrls[platform] ?? '';
      }
      _errorMessage = null;
    });
  }

  Future<void> _handleImport() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final instanceId = ref.read(personalizationProvider).instanceId.isNotEmpty
          ? ref.read(personalizationProvider).instanceId
          : await PersonalizationNotifier.getOrCreateInstanceId();
      final importer = ref.read(universalPlaylistImporterProvider);
      final playlist = await importer.importPlaylist(input, instanceId: instanceId);

      // Save to state & local offline storage & instance backup
      await ref.read(importedPlaylistsProvider.notifier).addPlaylist(playlist);
      ref.read(activePlaylistProvider.notifier).state = playlist;

      // Automatically personalize user identity from public playlist owner
      final owner = playlist.ownerName?.trim();
      if (owner != null &&
          owner.isNotEmpty &&
          !['spotify', 'user', 'spotify user', 'apple music', 'youtube'].contains(owner.toLowerCase())) {
        ref.read(personalizationProvider.notifier).updateProfile(
          userName: owner,
          instanceName: "$owner's Symphony",
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF18181B),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
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
          _errorMessage = e
              .toString()
              .replaceFirst('FormatException: ', '')
              .replaceFirst('AudioStreamResolutionException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const platforms = ['Spotify', 'YouTube', 'Apple Music'];

    return Dialog(
      backgroundColor: const Color(0xFF121214),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF27272A), width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(26.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E2E34), width: 1),
                    ),
                    child: const Center(
                      child: Icon(Icons.add_to_photos_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Import Playlist',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Spotify • YouTube • Apple Music',
                          style: TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF71717A), size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Platform Selection Chips
              const Text(
                'Source Platform',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFA1A1AA)),
              ),
              const SizedBox(height: 8),

              Row(
                children: platforms.map((platform) {
                  final isSelected = _selectedPlatform == platform;
                  final icon = switch (platform) {
                    'Spotify' => Icons.album_rounded,
                    'YouTube' => Icons.play_circle_outline_rounded,
                    'Apple Music' => Icons.music_note_rounded,
                    _ => Icons.music_note,
                  };

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: platform != platforms.last ? 8.0 : 0.0),
                      child: InkWell(
                        onTap: () => _onSelectPlatform(platform),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : const Color(0xFF18181B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.white : const Color(0xFF27272A),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 16,
                                color: isSelected ? Colors.black : const Color(0xFFA1A1AA),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                platform,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              // Dynamic Input Label & Field
              Text(
                _inputLabels[_selectedPlatform] ?? 'Playlist Link',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFA1A1AA)),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _inputController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: _placeholders[_selectedPlatform] ?? 'Paste playlist URL...',
                  hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF18181B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white, width: 1.2),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                ),
              ],

              const SizedBox(height: 16),
              const Text(
                'Example Presets:',
                style: TextStyle(fontSize: 11, color: Color(0xFF71717A)),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _getFilteredPresets().map((p) => _buildPresetChip(p.name, p.url, p.source)).toList(),
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleImport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          )
                        : const Text('Import & Play', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<({String name, String url, String source})> _getFilteredPresets() {
    return switch (_selectedPlatform) {
      'Spotify' => [
          (name: "Today's Top Hits (100 tracks)", url: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M', source: 'Spotify'),
          (name: 'Mega Hit Mix', url: 'https://open.spotify.com/playlist/37i9dQZF1DXbYM3nMM0oPk', source: 'Spotify'),
        ],
      'YouTube' => [
          (name: 'Pop Hits Essentials', url: 'https://www.youtube.com/playlist?list=PL4fGSIFgk5n0vF4P4V3d9_aF80hD_lD7w', source: 'YouTube'),
        ],
      'Apple Music' => [
          (name: 'Apple Music Top 50 Chart', url: 'https://itunes.apple.com/us/rss/topsongs/limit=50/json', source: 'Apple Music'),
        ],
      _ => <({String name, String url, String source})>[],
    };
  }

  Widget _buildPresetChip(String label, String url, String source) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: const Color(0xFF1E1E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF2E2E34), width: 0.8),
      ),
      onPressed: () {
        setState(() {
          _inputController.text = url;
          _errorMessage = null;
        });
      },
    );
  }
}
