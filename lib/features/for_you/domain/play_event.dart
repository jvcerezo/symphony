import '../../audio_player/domain/entities/track.dart';

/// How a play of a song ended.
enum PlayOutcome {
  /// Heard to (nearly) the end.
  completed,

  /// Heard for a while, then left.
  partial,

  /// Left within the first seconds: a signal the user didn't want it.
  skipped;

  /// Classifies a play from how long it was heard against the song's length.
  static PlayOutcome of({required Duration listened, required Duration length}) {
    final skipLimit =
        length > Duration.zero && length < const Duration(seconds: 60) ? length * 0.5 : const Duration(seconds: 30);
    if (listened < skipLimit) return PlayOutcome.skipped;
    // The last seconds are often an outro or silence; on short songs,
    // only a tenth of the song.
    final tail = length * 0.1 < const Duration(seconds: 15) ? length * 0.1 : const Duration(seconds: 15);
    if (length > Duration.zero && (listened >= length * 0.8 || length - listened <= tail)) {
      return PlayOutcome.completed;
    }
    return PlayOutcome.partial;
  }
}

/// One play of a song on this device.
class PlayEvent {
  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration length;
  final Duration listened;
  final DateTime at;
  final PlayOutcome outcome;

  const PlayEvent({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    required this.length,
    required this.listened,
    required this.at,
    required this.outcome,
  });

  factory PlayEvent.of(Track track, {required Duration listened, required Duration length, required DateTime at}) =>
      PlayEvent(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        artworkUrl: track.artworkUri?.toString(),
        length: length,
        listened: listened,
        at: at,
        outcome: PlayOutcome.of(listened: listened, length: length),
      );

  /// Same song whatever source it came from (a Spotify import and a search
  /// result of one song have different ids).
  String get songKey => songKeyOf(title, artist);

  /// The lead artist, used to group a song's plays by artist.
  String get leadArtist => leadArtistOf(artist);

  Track toTrack() => Track(
        id: trackId,
        title: title,
        artist: artist,
        album: album,
        expectedDuration: length > Duration.zero ? length : null,
        artworkUri: artworkUrl == null ? null : Uri.tryParse(artworkUrl!),
      );

  Map<String, dynamic> toJson() => {
        'id': trackId,
        't': title,
        'a': artist,
        if (album != null && album!.isNotEmpty) 'al': album,
        if (artworkUrl != null) 'art': artworkUrl,
        'len': length.inMilliseconds,
        'ms': listened.inMilliseconds,
        'at': at.millisecondsSinceEpoch,
        'o': outcome.index,
      };

  static PlayEvent? fromJson(Map<String, dynamic> json) {
    try {
      final o = (json['o'] as num).toInt();
      return PlayEvent(
        trackId: json['id'] as String,
        title: json['t'] as String,
        artist: json['a'] as String,
        album: json['al'] as String?,
        artworkUrl: json['art'] as String?,
        length: Duration(milliseconds: (json['len'] as num).toInt()),
        listened: Duration(milliseconds: (json['ms'] as num).toInt()),
        at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
        outcome: PlayOutcome.values[o.clamp(0, PlayOutcome.values.length - 1)],
      );
    } catch (_) {
      return null;
    }
  }
}

final _featuring = RegExp(r'\s*(?:,|&|\bfeat\.?|\bft\.?|\bfeaturing\b|\bx\b|\bwith\b)\s*', caseSensitive: false);
final _bracketed = RegExp(r'\s*[\(\[].*?[\)\]]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// "Olivia Rodrigo, Taylor Swift" → "Olivia Rodrigo".
String leadArtistOf(String artist) {
  final lead = artist.split(_featuring).firstWhere((s) => s.trim().isNotEmpty, orElse: () => artist);
  return lead.trim();
}

/// Lowercase letters and digits only, for comparing names.
String normalizeName(String s) => s.toLowerCase().replaceAll(_nonWord, ' ').trim();

/// One key per song: lead artist and title without "(Remastered)" etc.
String songKeyOf(String title, String artist) =>
    '${normalizeName(leadArtistOf(artist))}|${normalizeName(title.replaceAll(_bracketed, ''))}';
