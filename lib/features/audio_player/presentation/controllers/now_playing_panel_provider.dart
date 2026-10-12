import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side panels next to the player: the play queue and lyrics.
enum NowPlayingPanel { queue, lyrics }

/// The open side panel on desktop, or null when closed.
final nowPlayingPanelProvider = StateProvider<NowPlayingPanel?>((ref) => null);
