import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../../jam/data/jam_transport.dart';
import '../../../jam/presentation/jam_panel.dart';
import '../../../lyrics/presentation/lyrics_panel.dart';
import '../../domain/entities/track.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/now_playing_tint_provider.dart';
import '../widgets/playback_mode_buttons.dart';
import '../widgets/queue_panel.dart';
import '../widgets/symphony_artwork.dart';

/// Shared by the mini player's cover and the Now Playing cover, so the
/// artwork flies between them.
const nowPlayingArtworkHeroTag = 'now-playing-artwork';

/// Opens the full-screen Now Playing view (from the mini player). It is a
/// page route rather than a bottom sheet so the cover can fly up into it.
Future<void> showMobileNowPlaying(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const _SwipeDownToClose(child: MobileNowPlayingSheet()),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          child: child,
        );
      },
    ),
  );
}

/// Follows a downward drag and closes once it is far or fast enough;
/// otherwise springs back.
class _SwipeDownToClose extends StatefulWidget {
  final Widget child;

  const _SwipeDownToClose({required this.child});

  @override
  State<_SwipeDownToClose> createState() => _SwipeDownToCloseState();
}

class _SwipeDownToCloseState extends State<_SwipeDownToClose> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _offset = _from * (1 - Curves.easeOut.transform(_back.value))));
  double _offset = 0;
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _offset = math.max(0, _offset + d.delta.dy)),
      onVerticalDragEnd: (d) {
        if (_offset > 140 || (d.primaryVelocity ?? 0) > 800) {
          Navigator.of(context).pop();
        } else {
          _from = _offset;
          _back.forward(from: 0);
        }
      },
      child: Transform.translate(offset: Offset(0, _offset), child: widget.child),
    );
  }
}

/// Large artwork, scrubber and full controls, with Lyrics, Queue and Jam
/// below, over a blurred copy of the cover and a slowly drifting glow in its
/// color. The cover sits full size while playing and shrinks back when
/// paused. Swipe down (or the chevron) to close.
class MobileNowPlayingSheet extends ConsumerStatefulWidget {
  const MobileNowPlayingSheet({super.key});

  @override
  ConsumerState<MobileNowPlayingSheet> createState() => _MobileNowPlayingSheetState();
}

class _MobileNowPlayingSheetState extends ConsumerState<MobileNowPlayingSheet> with SingleTickerProviderStateMixin {
  // Drives the drifting glow: one slow loop, only while a song plays, so a
  // paused screen draws nothing.
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 16));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDrift(ref.read(isPlayingProvider));
  }

  void _syncDrift(bool playing) {
    if (!playing || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isPlayingProvider, (_, playing) => _syncDrift(playing));
    final mediaItem = ref.watch(currentMediaItemStreamProvider).asData?.value;
    final state = ref.watch(playbackStateStreamProvider).asData?.value;
    final tint = ref.watch(nowPlayingTintProvider).valueOrNull ?? SymphonyTheme.cardActive;
    final handler = ref.read(audioHandlerProvider);

    if (mediaItem == null) {
      return const Material(
        color: SymphonyTheme.obsidian,
        child: Center(
          child: Text('Nothing playing', style: TextStyle(color: SymphonyTheme.textSecondary)),
        ),
      );
    }

    final isPlaying = state?.playing ?? false;
    final isBuffering = state?.processingState == AudioProcessingState.buffering ||
        state?.processingState == AudioProcessingState.loading;

    return Material(
      color: SymphonyTheme.obsidian,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(artUri: mediaItem.artUri, tint: tint, drift: _drift),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        iconSize: 30,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          'Now playing',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const Spacer(),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.maxWidth.clamp(0.0, MediaQuery.sizeOf(context).height * 0.42);
                      return AnimatedScale(
                        scale: isPlaying ? 1.0 : 0.86,
                        duration: const Duration(milliseconds: 450),
                        curve: isPlaying ? Curves.easeOutBack : Curves.easeOutCubic,
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: tint),
                          duration: const Duration(milliseconds: 700),
                          builder: (context, glow, child) => AnimatedContainer(
                            duration: const Duration(milliseconds: 450),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: (glow ?? tint).withValues(alpha: isPlaying ? 0.55 : 0.2),
                                  blurRadius: 48,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: child,
                          ),
                          child: Hero(
                            tag: nowPlayingArtworkHeroTag,
                            child: SymphonyArtwork(
                              artworkUri: mediaItem.artUri,
                              track: Track(
                                id: mediaItem.id,
                                title: mediaItem.title,
                                artist: mediaItem.artist ?? '',
                                album: mediaItem.album,
                                artworkUri: mediaItem.artUri,
                              ),
                              size: size,
                              borderRadius: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mediaItem.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mediaItem.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<Duration>(
                    stream: AudioService.position,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final total = mediaItem.duration ?? Duration.zero;
                      final totalMs = total.inMilliseconds.toDouble();
                      final posMs = position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: posMs,
                              max: totalMs > 0 ? totalMs : 1.0,
                              onChanged: (v) => handler.seek(Duration(milliseconds: v.round())),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_format(position), style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12)),
                                Text(_format(total), style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const ShuffleButton(iconSize: 24, constraints: BoxConstraints(minWidth: 48, minHeight: 48)),
                      IconButton(
                        tooltip: 'Previous',
                        iconSize: 36,
                        icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                        onPressed: handler.skipToPrevious,
                      ),
                      SizedBox(
                        width: 68,
                        height: 68,
                        child: IconButton.filled(
                          tooltip: isPlaying ? 'Pause' : 'Play',
                          style: IconButton.styleFrom(backgroundColor: Colors.white),
                          iconSize: 36,
                          icon: isBuffering
                              ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                                )
                              : PlayPauseIcon(isPlaying: isPlaying, size: 36),
                          onPressed: isPlaying ? handler.pause : handler.play,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        iconSize: 36,
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                        onPressed: handler.skipToNext,
                      ),
                      const RepeatButton(iconSize: 24, constraints: BoxConstraints(minWidth: 48, minHeight: 48)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SheetButton(
                          icon: Icons.mic_none_outlined,
                          label: 'Lyrics',
                          onPressed: () => _openPanel(context, 'Lyrics', const LyricsPanel(fontSize: 24)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetButton(
                          icon: Icons.queue_music_rounded,
                          label: 'Queue',
                          onPressed: () => _openPanel(context, 'Queue', const QueuePanel()),
                        ),
                      ),
                      if (lanJamSupported) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SheetButton(
                            icon: Icons.groups_rounded,
                            label: 'Jam',
                            onPressed: () => openJam(context, ref),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _openPanel(BuildContext context, String title, Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: SymphonyTheme.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: SymphonyTheme.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// The cover, hugely blurred and dimmed, under a glow in [tint] that drifts
/// slowly around the screen, fading to black behind the controls.
///
/// The blur is the cover decoded 8 pixels wide and stretched smoothly: it
/// looks like a live blur, which would cost the GPU every frame the glow
/// moves and heat the phone.
class _Backdrop extends StatelessWidget {
  final Uri? artUri;
  final Color tint;
  final Animation<double> drift;

  const _Backdrop({required this.artUri, required this.tint, required this.drift});

  @override
  Widget build(BuildContext context) {
    final art = artUri;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (art != null && (art.isScheme('http') || art.isScheme('https')))
          RepaintBoundary(
            child: Opacity(
              opacity: 0.45,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 700),
                child: Image.network(
                  art.toString(),
                  key: ValueKey(art),
                  cacheWidth: 8,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        RepaintBoundary(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: tint),
            duration: const Duration(milliseconds: 900),
            builder: (context, color, _) => AnimatedBuilder(
              animation: drift,
              builder: (context, _) {
                final t = drift.value * 2 * math.pi;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(math.sin(t) * 0.7, -0.5 + math.cos(t * 2) * 0.25),
                      radius: 1.1,
                      colors: [(color ?? tint).withValues(alpha: 0.6), Colors.transparent],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Darkens the lower half so the controls stay readable.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8), SymphonyTheme.obsidian],
              stops: const [0.25, 0.7, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SheetButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        // Three share a row on narrow phones.
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        shape: const StadiumBorder(),
      ),
    );
  }
}
