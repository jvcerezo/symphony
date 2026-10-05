import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/audio_stream_resolver_service.dart';

void main() {
  group('AudioStreamResolverCandidateScoring', () {
    test('Disqualifies 60-minute Elden Ring gameplay podcast when searching for 3m25s song', () {
      final score = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'Elden Ring Gameplay Walkthrough Part 23 - That Smile is a Trap Boss Fight Podcast',
        videoAuthor: '1ShotPlays',
        durationSec: 3600, // 60 minutes
        targetTitle: 'That Smile is a Trap',
        targetArtist: 'Auric Veil',
        expectedDurationMs: 205000, // 3m 25s
      );

      // Must be heavily negative / disqualified
      expect(score, lessThan(0));
    });

    test('Scores authentic studio track with Topic channel and matching duration highly', () {
      final score = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'That Smile is a Trap',
        videoAuthor: 'Auric Veil - Topic',
        durationSec: 205, // exact 3m 25s
        targetTitle: 'That Smile is a Trap',
        targetArtist: 'Auric Veil',
        expectedDurationMs: 205000, // 3m 25s
      );

      // Must exceed 120 confidence threshold
      expect(score, greaterThanOrEqualTo(120));
    });

    test('Disqualifies video with red flags even if title contains some matching words', () {
      final score = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'Blinding Lights Reaction and Gameplay review',
        videoAuthor: 'RandomGamer',
        durationSec: 200,
        targetTitle: 'Blinding Lights',
        targetArtist: 'The Weeknd',
        expectedDurationMs: 200000,
      );

      expect(score, equals(-9999));
    });

    test('Disqualifies video when none of the title words match', () {
      final score = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'Something Completely Unrelated',
        videoAuthor: 'The Weeknd - Topic',
        durationSec: 200,
        targetTitle: 'Blinding Lights',
        targetArtist: 'The Weeknd',
        expectedDurationMs: 200000,
      );

      expect(score, equals(-9999));
    });

    test('Disqualifies duration mismatch greater than 80 seconds', () {
      final score = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'Blinding Lights Official Audio',
        videoAuthor: 'The Weeknd',
        durationSec: 350, // 5m 50s vs 3m 20s (diff 150s)
        targetTitle: 'Blinding Lights',
        targetArtist: 'The Weeknd',
        expectedDurationMs: 200000, // 3m 20s
      );

      expect(score, equals(-9999));
    });

    test('Prefers official audio and lyric videos over generic re-uploads', () {
      final officialScore = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'Starboy (Official Audio)',
        videoAuthor: 'The Weeknd',
        durationSec: 230,
        targetTitle: 'Starboy',
        targetArtist: 'The Weeknd',
        expectedDurationMs: 230000,
      );

      final unofficialScore = AudioStreamResolverService.scoreVideoCandidate(
        videoTitle: 'Starboy',
        videoAuthor: 'MusicFan123',
        durationSec: 230,
        targetTitle: 'Starboy',
        targetArtist: 'The Weeknd',
        expectedDurationMs: 230000,
      );

      expect(officialScore, greaterThan(unofficialScore));
    });
  });
}
