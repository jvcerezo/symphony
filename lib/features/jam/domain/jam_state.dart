import '../../audio_player/domain/entities/track.dart';

/// Most guests a Jam takes at once.
const jamMaxGuests = 8;

final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Whether [id] looks like a YouTube video id.
bool isYouTubeVideoId(String? id) => id != null && _videoIdPattern.hasMatch(id);

/// A queue entry as it travels between Jam devices.
///
/// [entry] tells two copies of the same song in the queue apart; it is the
/// host's id for that queue slot. [videoId] is the YouTube upload the host
/// plays, when known, so guests play the very same audio.
class JamTrack {
  final int entry;
  final String sourceId;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? artworkUrl;
  final String? videoId;

  const JamTrack({
    this.entry = 0,
    required this.sourceId,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.artworkUrl,
    this.videoId,
  });

  factory JamTrack.fromTrack(Track track, {int entry = 0, String? videoId}) {
    final art = track.artworkUri;
    return JamTrack(
      entry: entry,
      sourceId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationMs: track.expectedDuration?.inMilliseconds,
      // A file on the host's disk means nothing to a guest.
      artworkUrl: art != null && (art.scheme == 'https' || art.scheme == 'http') ? art.toString() : null,
      videoId: isYouTubeVideoId(videoId) ? videoId : null,
    );
  }

  /// The song as a [Track] on this device. A known upload becomes a `yt_`
  /// id, which the resolver plays directly instead of searching for a match.
  Track toTrack() {
    final art = artworkUrl == null ? null : Uri.tryParse(artworkUrl!);
    final duration = durationMs;
    return Track(
      id: videoId != null ? 'yt_$videoId' : sourceId,
      title: title,
      artist: artist,
      album: album,
      expectedDuration: duration == null ? null : Duration(milliseconds: duration),
      artworkUri: art,
    );
  }

  Map<String, Object?> toJson() => {
        'entry': entry,
        'sourceId': sourceId,
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        if (durationMs != null) 'durationMs': durationMs,
        if (artworkUrl != null) 'artworkUrl': artworkUrl,
        if (videoId != null) 'videoId': videoId,
      };

  factory JamTrack.fromJson(Map<String, Object?> json) {
    final videoId = json['videoId'] as String?;
    return JamTrack(
      entry: json['entry'] as int? ?? 0,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      durationMs: json['durationMs'] as int?,
      artworkUrl: json['artworkUrl'] as String?,
      videoId: isYouTubeVideoId(videoId) ? videoId : null,
    );
  }
}

/// What the host is playing, at host time [atHostMs].
class JamState {
  /// Only goes up; guests drop anything older than what they have.
  final int rev;
  final List<JamTrack> queue;
  final int index;

  /// True only while the host's audio is actually playing (not loading).
  final bool playing;
  final int positionMs;
  final int atHostMs;

  const JamState({
    required this.rev,
    required this.queue,
    required this.index,
    required this.playing,
    required this.positionMs,
    required this.atHostMs,
  });

  static const empty = JamState(rev: 0, queue: [], index: -1, playing: false, positionMs: 0, atHostMs: 0);

  JamTrack? get current => index >= 0 && index < queue.length ? queue[index] : null;

  /// Where the host's song is at host time [hostNowMs].
  Duration positionAt(int hostNowMs) {
    final ms = playing ? positionMs + (hostNowMs - atHostMs) : positionMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  Map<String, Object?> toJson() => {
        'rev': rev,
        'queue': [for (final t in queue) t.toJson()],
        'index': index,
        'playing': playing,
        'positionMs': positionMs,
        'atHostMs': atHostMs,
      };

  factory JamState.fromJson(Map<String, Object?> json) => JamState(
        rev: json['rev'] as int,
        queue: [for (final t in json['queue'] as List) JamTrack.fromJson((t as Map).cast<String, Object?>())],
        index: json['index'] as int,
        playing: json['playing'] as bool,
        positionMs: json['positionMs'] as int,
        atHostMs: json['atHostMs'] as int,
      );
}

class JamMember {
  final String id;
  final String name;
  final bool isHost;

  const JamMember({required this.id, required this.name, this.isHost = false});

  Map<String, Object?> toJson() => {'id': id, 'name': name, if (isHost) 'isHost': true};

  factory JamMember.fromJson(Map<String, Object?> json) =>
      JamMember(id: json['id'] as String, name: json['name'] as String, isHost: json['isHost'] as bool? ?? false);

  @override
  bool operator ==(Object other) => other is JamMember && other.id == id && other.name == name && other.isHost == isHost;

  @override
  int get hashCode => Object.hash(id, name, isHost);
}

/// What guests may do. Adding songs is always allowed.
class JamPermissions {
  /// Play, pause, seek, skip, jump, and remove or reorder queued songs.
  final bool guestsControlPlayback;

  const JamPermissions({this.guestsControlPlayback = true});

  Map<String, Object?> toJson() => {'guestsControlPlayback': guestsControlPlayback};

  factory JamPermissions.fromJson(Map<String, Object?> json) =>
      JamPermissions(guestsControlPlayback: json['guestsControlPlayback'] as bool? ?? true);
}
