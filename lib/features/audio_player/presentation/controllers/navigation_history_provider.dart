import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import 'audio_player_providers.dart';

class NavHistoryEntry {
  final String tab;
  final SpotifyPlaylist? playlist;

  const NavHistoryEntry({
    required this.tab,
    this.playlist,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavHistoryEntry &&
          runtimeType == other.runtimeType &&
          tab == other.tab &&
          playlist?.id == other.playlist?.id;

  @override
  int get hashCode => tab.hashCode ^ (playlist?.id.hashCode ?? 0);
}

class NavHistoryState {
  final List<NavHistoryEntry> history;
  final int currentIndex;

  const NavHistoryState({
    this.history = const [],
    this.currentIndex = -1,
  });

  bool get canGoBack => currentIndex > 0;
  bool get canGoForward => currentIndex >= 0 && currentIndex < history.length - 1;

  NavHistoryEntry? get current =>
      currentIndex >= 0 && currentIndex < history.length ? history[currentIndex] : null;
}

class NavHistoryNotifier extends StateNotifier<NavHistoryState> {
  NavHistoryNotifier() : super(const NavHistoryState());

  bool _isNavigating = false;

  void record(String tab, SpotifyPlaylist? playlist) {
    if (_isNavigating) return;

    final entry = NavHistoryEntry(tab: tab, playlist: playlist);
    if (state.current == entry) return;

    // Discard any forward history if we navigated to a new page
    final newHistory = state.currentIndex >= 0
        ? state.history.sublist(0, state.currentIndex + 1)
        : <NavHistoryEntry>[];

    newHistory.add(entry);

    state = NavHistoryState(
      history: newHistory,
      currentIndex: newHistory.length - 1,
    );
  }

  void goBack(dynamic ref) {
    if (!state.canGoBack) return;
    final targetIndex = state.currentIndex - 1;
    final target = state.history[targetIndex];

    _isNavigating = true;
    state = NavHistoryState(
      history: state.history,
      currentIndex: targetIndex,
    );

    ref.read(activeNavTabProvider.notifier).state = target.tab;
    ref.read(activePlaylistProvider.notifier).state = target.playlist;
    _isNavigating = false;
  }

  void goForward(dynamic ref) {
    if (!state.canGoForward) return;
    final targetIndex = state.currentIndex + 1;
    final target = state.history[targetIndex];

    _isNavigating = true;
    state = NavHistoryState(
      history: state.history,
      currentIndex: targetIndex,
    );

    ref.read(activeNavTabProvider.notifier).state = target.tab;
    ref.read(activePlaylistProvider.notifier).state = target.playlist;
    _isNavigating = false;
  }
}

final navigationHistoryProvider =
    StateNotifierProvider<NavHistoryNotifier, NavHistoryState>((ref) {
  return NavHistoryNotifier();
});
