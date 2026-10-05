import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import '../../domain/entities/track.dart';

final artworkResolverProvider = Provider<ArtworkResolverService>((ref) {
  final service = ArtworkResolverService();
  ref.onDispose(() => service.dispose());
  return service;
});

class SymphonyArtwork extends ConsumerStatefulWidget {
  final Track? track;
  final Uri? artworkUri;
  final double size;
  final double borderRadius;
  final bool hasGlow;

  const SymphonyArtwork({
    super.key,
    this.track,
    this.artworkUri,
    required this.size,
    this.borderRadius = 6.0,
    this.hasGlow = false,
  });

  @override
  ConsumerState<SymphonyArtwork> createState() => _SymphonyArtworkState();
}

class _SymphonyArtworkState extends ConsumerState<SymphonyArtwork> {
  Uri? _resolvedUri;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _checkArtwork();
  }

  @override
  void didUpdateWidget(covariant SymphonyArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track?.id != oldWidget.track?.id || widget.artworkUri != oldWidget.artworkUri) {
      _checkArtwork();
    }
  }

  void _checkArtwork() {
    if (widget.artworkUri != null) {
      _resolvedUri = widget.artworkUri;
      return;
    }

    if (widget.track?.artworkUri != null) {
      _resolvedUri = widget.track!.artworkUri;
      return;
    }

    if (widget.track != null && !_isResolving) {
      _isResolving = true;
      ref.read(artworkResolverProvider).resolveArtwork(widget.track!).then((uri) {
        if (mounted && uri != null) {
          setState(() {
            _resolvedUri = uri;
            _isResolving = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final borderRadius = widget.borderRadius;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: widget.hasGlow
            ? [
                BoxShadow(
                  color: SymphonyTheme.primary.withAlpha(140),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _resolvedUri != null
            ? Image.network(
                _resolvedUri.toString(),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildVibrantFallback(size),
              )
            : _buildVibrantFallback(size),
      ),
    );
  }

  Widget _buildVibrantFallback(double size) {
    final title = widget.track?.title ?? 'S';
    final artist = widget.track?.artist ?? 'S';
    final initial = title.isNotEmpty ? title[0].toUpperCase() : 'S';

    // Generate stable color based on track title hash
    final hash = (title.hashCode ^ artist.hashCode).abs();
    final hue = (hash % 360).toDouble();
    final color1 = HSLColor.fromAHSL(1.0, hue, 0.75, 0.45).toColor();
    final color2 = HSLColor.fromAHSL(1.0, (hue + 45) % 360, 0.85, 0.25).toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color1, color2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: size > 40
            ? Text(
                initial,
                style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withAlpha(200),
                ),
              )
            : Icon(Icons.music_note, size: size * 0.5, color: Colors.white70),
      ),
    );
  }
}
