import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/metadata_search/data/services/artwork_resolver_service.dart';
import 'package:symphony/features/playlist_import/data/services/spotify_embed_scraper_service.dart';
import 'package:symphony/features/playlist_import/data/services/universal_playlist_importer_service.dart';
import 'package:symphony/features/playlist_import/domain/entities/spotify_playlist.dart';

void main() {
  group('SpotifyEmbedScraperService URL & Embed Tests', () {
    final scraper = SpotifyEmbedScraperService();

    test('extractPlaylistId parses various Spotify URL formats correctly', () {
      expect(
        scraper.extractPlaylistId('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=123'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
      expect(
        scraper.extractPlaylistId('https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
      expect(
        scraper.extractPlaylistId('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        equals('37i9dQZF1DXcBWIGoYBM5M'),
      );
      expect(scraper.extractPlaylistId('37i9dQZF1DXcBWIGoYBM5M'), equals('37i9dQZF1DXcBWIGoYBM5M'));
    });

    test('extractPlaylistId returns null for invalid input', () {
      expect(scraper.extractPlaylistId('https://invalid.com/something/else'), isNull);
    });

    test('Curated fallback tracks have distinct individual artwork URIs', () async {
      final playlist = await scraper.importPlaylist('37i9dQZF1DXcBWIGoYBM5M');
      expect(playlist.tracks, isNotEmpty);
      final artUris = playlist.tracks.map((t) => t.artworkUri?.toString()).toSet();
      // Ensure tracks do not all have the exact same cover image
      expect(artUris.length, greaterThan(1));
    });
  });

  group('ArtworkResolverService Title Cleaning Tests', () {
    test('cleanTrackTitle strips feat, remastered, and extraneous tags', () {
      expect(
        ArtworkResolverService.cleanTrackTitle('Starboy (feat. Daft Punk)'),
        equals('Starboy'),
      );
      expect(
        ArtworkResolverService.cleanTrackTitle('Blinding Lights - Remastered 2020'),
        equals('Blinding Lights'),
      );
      expect(
        ArtworkResolverService.cleanTrackTitle('Stay - Radio Edit'),
        equals('Stay'),
      );
    });
  });

  group('UniversalPlaylistImporterService Source Detection Tests', () {
    final importer = UniversalPlaylistImporterService();

    test('detects Spotify sources', () {
      expect(
        importer.detectSource('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        equals(PlaylistSourceType.spotify),
      );
    });

    test('detects YouTube sources', () {
      expect(
        importer.detectSource('https://www.youtube.com/playlist?list=PL4fGSIFgk5n0vF4P4V3d9_aF80hD_lD7w'),
        equals(PlaylistSourceType.youtube),
      );
      expect(
        importer.detectSource('https://music.youtube.com/playlist?list=RDCLAK5uy_k123'),
        equals(PlaylistSourceType.youtube),
      );
    });

    test('detects Deezer sources', () {
      expect(
        importer.detectSource('https://www.deezer.com/playlist/908622995'),
        equals(PlaylistSourceType.deezer),
      );
    });

    test('detects Apple Music sources', () {
      expect(
        importer.detectSource('https://music.apple.com/us/playlist/todays-hits/pl.12345'),
        equals(PlaylistSourceType.appleMusic),
      );
    });

    test('detects Smart Mix queries', () {
      expect(
        importer.detectSource('Taylor Swift Top Songs'),
        equals(PlaylistSourceType.smartMix),
      );
    });
  });

  group('Playlist Persistence & Serialization Tests', () {
    test('SpotifyPlaylist toJson and fromJson roundtrip accurately', () {
      final sample = SpotifyPlaylist(
        id: 'user_pl_1',
        title: 'My Custom Jams',
        description: 'Vibes only',
        ownerName: 'Jet',
        source: 'Spotify',
        tracks: [
          Track(
            id: 'tr_1',
            title: 'Midnight City',
            artist: 'M83',
            album: 'Hurry Up, We\'re Dreaming',
            expectedDuration: const Duration(minutes: 4, seconds: 4),
            artworkUri: Uri.parse('https://example.com/art.jpg'),
          ),
        ],
      );

      final json = sample.toJson();
      final restored = SpotifyPlaylist.fromJson(json);

      expect(restored.id, equals('user_pl_1'));
      expect(restored.title, equals('My Custom Jams'));
      expect(restored.ownerName, equals('Jet'));
      expect(restored.tracks.length, equals(1));
      expect(restored.tracks.first.title, equals('Midnight City'));
      expect(restored.tracks.first.expectedDuration, equals(const Duration(minutes: 4, seconds: 4)));
    });

    test('ImportedPlaylistsNotifier restores playlists from SharedPreferences', () async {
      final customJson = [
        {
          'id': 'my_custom_123',
          'title': 'Offline Roadtrip',
          'description': 'Saved for offline',
          'ownerName': 'TestListener',
          'source': 'Spotify',
          'tracks': [
            {
              'id': 'tr_x',
              'title': 'Fast Car',
              'artist': 'Luke Combs',
              'album': 'Gettin\' Old',
              'durationMs': 265000,
              'artworkUri': null,
            }
          ]
        }
      ];

      SharedPreferences.setMockInitialValues({
        'symphony_user_playlists': jsonEncode(customJson),
      });

      final notifier = ImportedPlaylistsNotifier();
      // Allow async _initAndLoad to execute
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = notifier.state;
      expect(state.any((p) => p.id == 'my_custom_123'), isTrue);
      final restored = state.firstWhere((p) => p.id == 'my_custom_123');
      expect(restored.title, equals('Offline Roadtrip'));
      expect(restored.ownerName, equals('TestListener'));
      expect(restored.tracks.first.title, equals('Fast Car'));
    });
  });
}
