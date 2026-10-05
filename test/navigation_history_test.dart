import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/controllers/navigation_history_provider.dart';
import 'package:symphony/features/playlist_import/domain/entities/spotify_playlist.dart';

void main() {
  group('NavigationHistoryNotifier', () {
    test('Initial state has no back or forward history', () {
      final container = ProviderContainer();
      final history = container.read(navigationHistoryProvider);

      expect(history.canGoBack, isFalse);
      expect(history.canGoForward, isFalse);
      expect(history.currentIndex, -1);
    });

    test('Records navigation entries and enables canGoBack', () {
      final container = ProviderContainer();
      final notifier = container.read(navigationHistoryProvider.notifier);

      notifier.record('home', null);
      expect(container.read(navigationHistoryProvider).canGoBack, isFalse);
      expect(container.read(navigationHistoryProvider).canGoForward, isFalse);

      notifier.record('search', null);
      expect(container.read(navigationHistoryProvider).canGoBack, isTrue);
      expect(container.read(navigationHistoryProvider).canGoForward, isFalse);
      expect(container.read(navigationHistoryProvider).currentIndex, 1);
    });

    test('Ignores duplicate sequential navigation', () {
      final container = ProviderContainer();
      final notifier = container.read(navigationHistoryProvider.notifier);

      notifier.record('home', null);
      notifier.record('home', null);

      expect(container.read(navigationHistoryProvider).history.length, 1);
    });

    test('goBack and goForward navigate correctly through history stack', () {
      final p1 = const SpotifyPlaylist(
        id: 'p1',
        title: 'Playlist 1',
        tracks: [],
      );
      final p2 = const SpotifyPlaylist(
        id: 'p2',
        title: 'Playlist 2',
        tracks: [],
      );

      final container = ProviderContainer();
      final notifier = container.read(navigationHistoryProvider.notifier);

      notifier.record('home', p1);
      notifier.record('home', p2);
      notifier.record('library', null);

      final stateBefore = container.read(navigationHistoryProvider);
      expect(stateBefore.currentIndex, 2);
      expect(stateBefore.canGoBack, isTrue);
      expect(stateBefore.canGoForward, isFalse);

      // Go back to p2
      notifier.goBack(container as dynamic);
      final stateAtP2 = container.read(navigationHistoryProvider);
      expect(stateAtP2.currentIndex, 1);
      expect(stateAtP2.canGoBack, isTrue);
      expect(stateAtP2.canGoForward, isTrue);
      expect(container.read(activeNavTabProvider), 'home');
      expect(container.read(activePlaylistProvider)?.id, 'p2');

      // Go back to p1
      notifier.goBack(container as dynamic);
      final stateAtP1 = container.read(navigationHistoryProvider);
      expect(stateAtP1.currentIndex, 0);
      expect(stateAtP1.canGoBack, isFalse);
      expect(stateAtP1.canGoForward, isTrue);
      expect(container.read(activeNavTabProvider), 'home');
      expect(container.read(activePlaylistProvider)?.id, 'p1');

      // Go forward to p2
      notifier.goForward(container as dynamic);
      expect(container.read(navigationHistoryProvider).currentIndex, 1);
      expect(container.read(activePlaylistProvider)?.id, 'p2');
    });

    test('Recording a new page after goBack discards forward history', () {
      final container = ProviderContainer();
      final notifier = container.read(navigationHistoryProvider.notifier);

      notifier.record('home', null);
      notifier.record('search', null);
      notifier.record('library', null);

      // Back to search
      notifier.goBack(container as dynamic);
      expect(container.read(navigationHistoryProvider).canGoForward, isTrue);

      // Record new tab 'settings'
      notifier.record('settings', null);
      final state = container.read(navigationHistoryProvider);
      expect(state.history.length, 3);
      expect(state.history[2].tab, 'settings');
      expect(state.canGoForward, isFalse);
      expect(state.canGoBack, isTrue);
    });
  });
}
