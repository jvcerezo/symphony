import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/artwork_colors.dart';
import '../../domain/entities/track.dart';
import 'audio_player_providers.dart';

/// The current song's cover color, used to tint the player bar, the Now
/// Playing view and the window glow. Null when nothing plays or the cover
/// has no readable color; widgets then keep the neutral look.
final nowPlayingTintProvider = FutureProvider<Color?>((ref) async {
  // Only a new song (or new cover) changes the tint, not position updates.
  final id = ref.watch(currentMediaItemStreamProvider.select((a) => a.asData?.value?.id));
  final artUri = ref.watch(currentMediaItemStreamProvider.select((a) => a.asData?.value?.artUri));
  if (id == null) return null;

  var art = artUri;
  if (art == null) {
    final item = ref.read(currentMediaItemStreamProvider).asData?.value;
    if (item == null) return null;
    art = await ref.read(artworkResolverProvider).resolveArtwork(
          Track(id: item.id, title: item.title, artist: item.artist ?? '', album: item.album),
        );
  }
  if (art == null) return null;
  return ref.watch(artworkColorProvider(art.toString()).future);
});
