import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/playlist_import/data/services/spotify_embed_scraper_service.dart';

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
  });
}
