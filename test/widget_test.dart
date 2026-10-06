import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony/main.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/playlist_import/domain/entities/spotify_playlist.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

void main() {
  testWidgets('SymphonyApp renders Spotify layout with playlist hero and tracks',
      (WidgetTester tester) async {
    final fakeHandler = SymphonyAudioHandler();
    final samplePlaylist = SpotifyPlaylist(
      id: 'test-playlist-1',
      title: 'Top Hits 2026',
      ownerName: 'Spotify',
      tracks: [
        Track(
          id: 'track-1',
          title: 'Starboy',
          artist: 'The Weeknd',
          album: 'Starboy LP',
          expectedDuration: const Duration(minutes: 3, seconds: 50),
        ),
        Track(
          id: 'track-2',
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          album: 'After Hours',
          expectedDuration: const Duration(minutes: 3, seconds: 20),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      fakeHandler.release();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(fakeHandler),
          activePlaylistProvider.overrideWith((ref) => samplePlaylist),
        ],
        child: const SymphonyApp(),
      ),
    );

    // Verify Playlist title renders in hero section
    expect(find.text('Top Hits 2026'), findsOneWidget);
    expect(find.text('PLAYLIST'), findsOneWidget);
    expect(find.text('Starboy'), findsOneWidget);
    expect(find.text('Blinding Lights'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });
}
