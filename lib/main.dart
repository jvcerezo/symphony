import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/audio_player/data/services/symphony_audio_handler.dart';
import 'features/audio_player/domain/entities/track.dart';
import 'features/audio_player/presentation/controllers/audio_player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background AudioService singleton
  final audioHandler = await AudioService.init(
    builder: () => SymphonyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.symphony.symphony.audio',
      androidNotificationChannelName: 'Symphony Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const SymphonyApp(),
    ),
  );
}

class SymphonyApp extends StatelessWidget {
  const SymphonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Symphony',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const SymphonyHomeScreen(),
    );
  }
}

class SymphonyHomeScreen extends ConsumerStatefulWidget {
  const SymphonyHomeScreen({super.key});

  @override
  ConsumerState<SymphonyHomeScreen> createState() => _SymphonyHomeScreenState();
}

class _SymphonyHomeScreenState extends ConsumerState<SymphonyHomeScreen> {
  final _titleController = TextEditingController(text: 'Blinding Lights');
  final _artistController = TextEditingController(text: 'The Weeknd');
  bool _isLoading = false;
  String? _statusMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _triggerPlayback() async {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();
    if (title.isEmpty || artist.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Resolving audio stream...';
    });

    final track = Track(
      id: '${artist}_$title'.replaceAll(' ', '_').toLowerCase(),
      title: title,
      artist: artist,
    );

    try {
      final handler = ref.read(audioHandlerProvider);
      await handler.playTrack(track);
      setState(() {
        _statusMessage = 'Now streaming';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Resolution error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Symphony Audio Player', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Direct Stream Resolution',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Track Title',
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _artistController,
                        decoration: InputDecoration(
                          labelText: 'Artist',
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _triggerPlayback,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(_isLoading ? 'Resolving...' : 'Play Stream'),
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _statusMessage!.contains('error') ? Colors.redAccent : Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Player Controls Card
              if (mediaItem != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF333333),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.music_note, color: Color(0xFF1DB954), size: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mediaItem.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mediaItem.artist ?? 'Unknown Artist',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: 42,
                            icon: Icon(
                              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: const Color(0xFF1DB954),
                            ),
                            onPressed: () {
                              final handler = ref.read(audioHandlerProvider);
                              if (isPlaying) {
                                handler.pause();
                              } else {
                                handler.play();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Position timeline
                      StreamBuilder<Duration>(
                        stream: AudioService.position,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final total = mediaItem.duration ?? Duration.zero;
                          final totalMs = total.inMilliseconds.toDouble();
                          final posMs = position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);

                          return Column(
                            children: [
                              Slider(
                                value: posMs,
                                max: totalMs > 0 ? totalMs : 1.0,
                                activeColor: const Color(0xFF1DB954),
                                inactiveColor: Colors.white24,
                                onChanged: (value) {
                                  ref.read(audioHandlerProvider).seek(Duration(milliseconds: value.round()));
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text(_formatDuration(total), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
