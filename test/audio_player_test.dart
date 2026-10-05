import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/audio_player/domain/entities/resolved_audio_stream.dart';
import 'package:symphony/core/errors/exceptions.dart';

void main() {
  group('Track Entity & MediaItem Conversion', () {
    test('Track correctly converts to MediaItem with duration', () {
      final track = Track(
        id: 'track-001',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        expectedDuration: const Duration(seconds: 200),
        artworkUri: Uri.parse('https://example.com/cover.jpg'),
        streamUri: Uri.parse('https://example.com/stream.mp3'),
      );

      final mediaItem = track.toMediaItem(actualDuration: const Duration(seconds: 202));

      expect(mediaItem.id, equals('track-001'));
      expect(mediaItem.title, equals('Blinding Lights'));
      expect(mediaItem.artist, equals('The Weeknd'));
      expect(mediaItem.album, equals('After Hours'));
      expect(mediaItem.duration, equals(const Duration(seconds: 202)));
      expect(mediaItem.artUri, equals(Uri.parse('https://example.com/cover.jpg')));
      expect(track.streamUri, equals(Uri.parse('https://example.com/stream.mp3')));

      final updated = track.copyWith(title: 'Save Your Tears');
      expect(updated.title, equals('Save Your Tears'));
      expect(updated.streamUri, equals(Uri.parse('https://example.com/stream.mp3')));
    });
  });

  group('ResolvedAudioStream Value Object', () {
    test('Stores resolved stream properties accurately', () {
      final stream = ResolvedAudioStream(
        streamUri: Uri.parse('https://rr1---sn.googlevideo.com/videoplayback'),
        duration: const Duration(seconds: 202),
        bitrateKbps: 160,
        format: 'webm',
        sourceVideoId: 'fHI8X480mxo',
      );

      expect(stream.bitrateKbps, equals(160));
      expect(stream.format, equals('webm'));
      expect(stream.sourceVideoId, equals('fHI8X480mxo'));
    });
  });

  group('Domain Exceptions', () {
    test('AudioStreamResolutionException contains message and cause', () {
      final exception = AudioStreamResolutionException(
        'Resolution failed',
        Exception('Network timeout'),
      );

      expect(exception.message, equals('Resolution failed'));
      expect(exception.toString(), contains('Network timeout'));
    });

    test('PlaybackInitializationException formats correctly', () {
      final exception = PlaybackInitializationException('Hardware failure');
      expect(exception.toString(), contains('Hardware failure'));
    });
  });
}
