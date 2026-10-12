import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/symphony_theme.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../domain/lyrics.dart';
import 'lyrics_providers.dart';

/// Lyrics for the song that's playing. Synced lyrics follow the song and
/// a tap on a line jumps there; plain lyrics just scroll.
class LyricsPanel extends ConsumerWidget {
  /// Text size of a lyric line; the mobile sheet uses larger type.
  final double fontSize;

  const LyricsPanel({super.key, this.fontSize = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemStreamProvider).asData?.value;
    if (mediaItem == null) {
      return const _LyricsMessage(
        icon: Icons.lyrics_outlined,
        title: 'Nothing playing',
        body: 'Play a song to see its lyrics here.',
      );
    }

    final handler = ref.read(audioHandlerProvider);
    final track = handler.currentTrack;
    final query = LyricsQuery(
      title: mediaItem.title,
      artist: mediaItem.artist ?? '',
      album: mediaItem.album,
      duration: track?.expectedDuration ?? mediaItem.duration,
    );

    return ref.watch(lyricsProvider(query)).when(
          loading: () => const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: SymphonyTheme.textSecondary),
            ),
          ),
          error: (_, __) => _LyricsMessage(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load lyrics",
            body: 'Check your connection and try again.',
            action: TextButton(
              onPressed: () => ref.invalidate(lyricsProvider(query)),
              child: const Text('Try again'),
            ),
          ),
          data: (lyrics) {
            if (lyrics == null || (!lyrics.hasText && !lyrics.instrumental)) {
              return const _LyricsMessage(
                icon: Icons.lyrics_outlined,
                title: 'No lyrics for this song',
                body: "We couldn't find lyrics for this one.",
              );
            }
            if (!lyrics.hasText) {
              return const _LyricsMessage(
                icon: Icons.piano_rounded,
                title: 'Instrumental',
                body: 'This song has no lyrics. Enjoy the music.',
              );
            }
            if (lyrics.isSynced) {
              return _SyncedLyrics(
                key: ValueKey(query),
                lyrics: lyrics,
                fontSize: fontSize,
                onSeek: handler.seek,
              );
            }
            return _PlainLyrics(text: lyrics.plainText!, fontSize: fontSize);
          },
        );
  }
}

class _SyncedLyrics extends StatefulWidget {
  final Lyrics lyrics;
  final double fontSize;
  final ValueChanged<Duration> onSeek;

  const _SyncedLyrics({super.key, required this.lyrics, required this.fontSize, required this.onSeek});

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  late final List<GlobalKey> _lineKeys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
  StreamSubscription<Duration>? _positionSub;
  int _active = -1;

  /// After the user scrolls, leave the view alone for a moment.
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _positionSub = AudioService.position.listen(_onPosition);
  }

  void _onPosition(Duration position) {
    final next = widget.lyrics.lineIndexAt(position);
    if (next == _active || !mounted) return;
    setState(() => _active = next);
    if (DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    final ctx = next >= 0 ? _lineKeys[next].currentContext : null;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < lines.length; i++)
              InkWell(
                key: _lineKeys[i],
                borderRadius: BorderRadius.circular(6),
                onTap: () => widget.onSeek(lines[i].time),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: i == _active
                          ? SymphonyTheme.textPrimary
                          : i < _active
                              ? SymphonyTheme.textSecondary
                              : SymphonyTheme.textMuted,
                    ),
                    child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const _LyricsCredit(),
          ],
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  final String text;
  final double fontSize;

  const _PlainLyrics({required this.text, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "These lyrics aren't synced to the song.",
            style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SelectableText(
            text.trim(),
            style: TextStyle(
              color: SymphonyTheme.textPrimary,
              // Plain lyrics are longer to read, so they run a little smaller.
              fontSize: fontSize * 0.8,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          const _LyricsCredit(),
        ],
      ),
    );
  }
}

class _LyricsCredit extends StatelessWidget {
  const _LyricsCredit();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Lyrics from LRCLIB',
      style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 11),
    );
  }
}

class _LyricsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _LyricsMessage({required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SymphonyTheme.textSecondary, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SymphonyTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
