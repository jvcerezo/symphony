import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/presentation/controllers/personalization_provider.dart';
import '../controllers/audio_player_providers.dart';

typedef _Preset = ({String name, String url});

class ImportPlaylistDialog extends ConsumerStatefulWidget {
  const ImportPlaylistDialog({super.key});

  @override
  ConsumerState<ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends ConsumerState<ImportPlaylistDialog> {
  String _selectedPlatform = 'Spotify'; // 'Spotify' | 'YouTube' | 'Apple Music'
  final _inputController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  static const _platforms = ['Spotify', 'YouTube', 'Apple Music'];

  static const Map<String, IconData> _icons = {
    'Spotify': Icons.album_rounded,
    'YouTube': Icons.play_circle_outline_rounded,
    'Apple Music': Icons.music_note_rounded,
  };

  static const Map<String, String> _placeholders = {
    'Spotify': 'open.spotify.com/playlist/…',
    'YouTube': 'youtube.com/playlist?list=…',
    'Apple Music': 'music.apple.com/…/playlist/…',
  };

  // Checked to open on 2026-10-12.
  static const Map<String, List<_Preset>> _presets = {
    'Spotify': [
      (name: "Today's Top Hits", url: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
      (name: 'Mega Hit Mix', url: 'https://open.spotify.com/playlist/37i9dQZF1DXbYM3nMM0oPk'),
    ],
    'YouTube': [
      (name: "Pop's Biggest Hits", url: 'https://www.youtube.com/playlist?list=RDCLAK5uy_nmS3YoxSwVVQk9lEQJ0UX4ZCjXsW_psU8'),
      (name: 'The Hit List', url: 'https://www.youtube.com/playlist?list=RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs'),
    ],
    'Apple Music': [
      (name: "Today's Hits", url: 'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb'),
    ],
  };

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _onSelectPlatform(String platform) {
    if (_selectedPlatform == platform) return;
    setState(() {
      _selectedPlatform = platform;
      _errorMessage = null;
    });
  }

  /// A pasted link picks its platform, so the tabs never disagree with it.
  void _onInputChanged(String text) {
    final s = text.toLowerCase();
    final detected = s.contains('spotify')
        ? 'Spotify'
        : s.contains('youtu')
            ? 'YouTube'
            : s.contains('apple.com')
                ? 'Apple Music'
                : null;
    setState(() {
      if (detected != null) _selectedPlatform = detected;
      _errorMessage = null;
    });
  }

  Future<void> _handleImport() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = 'Paste a playlist link first, or pick one below.');
      return;
    }

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
    final compact = MediaQuery.sizeOf(context).width < 480;

    return Dialog(
      backgroundColor: const Color(0xFF121214),
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF27272A), width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 20 : 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(compact),
              const SizedBox(height: 20),
              _buildPlatformTabs(compact),
              const SizedBox(height: 18),
              TextField(
                controller: _inputController,
                onChanged: _onInputChanged,
                onSubmitted: (_) => _isLoading ? null : _handleImport(),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: '$_selectedPlatform playlist link',
                  labelStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                  floatingLabelStyle: const TextStyle(color: Colors.white, fontSize: 13),
                  hintText: _placeholders[_selectedPlatform],
                  hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 13),
                  prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF71717A), size: 20),
                  filled: true,
                  fillColor: const Color(0xFF18181B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF27272A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
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
              const SizedBox(height: 18),
              const Text(
                'Or start with one of these',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFA1A1AA)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (_presets[_selectedPlatform] ?? const <_Preset>[]).map(_buildPresetChip).toList(),
              ),
              const SizedBox(height: 24),
              _buildActions(compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2E34), width: 1),
            ),
            child: const Icon(Icons.add_to_photos_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
        ],
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import a playlist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
              ),
              SizedBox(height: 4),
              Text(
                'Paste a link from Spotify, YouTube or Apple Music.',
                style: TextStyle(fontSize: 13, color: Color(0xFFA1A1AA), height: 1.3),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, color: Color(0xFF71717A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Three equal tabs. On a phone the icon sits above the name so
  /// "Apple Music" fits without cutting off.
  Widget _buildPlatformTabs(bool compact) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        children: _platforms.map((platform) {
          final selected = _selectedPlatform == platform;
          final color = selected ? Colors.black : const Color(0xFFA1A1AA);
          final icon = Icon(_icons[platform], size: compact ? 18 : 16, color: color);
          // Shrinks a little on the narrowest phones rather than cutting off.
          final label = FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              platform,
              maxLines: 1,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
          );
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: InkWell(
                onTap: () => _onSelectPlatform(platform),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10, horizontal: compact ? 4 : 6),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: compact
                      ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 4), label])
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [icon, const SizedBox(width: 7), Flexible(child: label)],
                        ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActions(bool compact) {
    final importButton = ElevatedButton(
      onPressed: _isLoading ? null : _handleImport,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        disabledBackgroundColor: Colors.white70,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
            )
          : const Text('Import & Play', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    );
    // On a phone the close button is enough; Import gets the full width.
    if (compact) return SizedBox(width: double.infinity, child: importButton);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFFA1A1AA), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        importButton,
      ],
    );
  }

  Widget _buildPresetChip(_Preset preset) {
    final picked = _inputController.text.trim() == preset.url;
    return ActionChip(
      avatar: Icon(
        picked ? Icons.check_rounded : _icons[_selectedPlatform],
        size: 16,
        color: picked ? Colors.black : const Color(0xFFA1A1AA),
      ),
      label: Text(
        preset.name,
        style: TextStyle(fontSize: 12, color: picked ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: picked ? Colors.white : const Color(0xFF1E1E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: picked ? Colors.white : const Color(0xFF2E2E34), width: 0.8),
      ),
      onPressed: () {
        setState(() {
          _inputController.text = preset.url;
          _errorMessage = null;
        });
      },
    );
  }
}
