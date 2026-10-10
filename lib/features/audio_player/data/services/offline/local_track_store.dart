import '../../../domain/entities/track.dart';
import 'local_track_store_stub.dart'
    if (dart.library.io) 'local_track_store_io.dart' as impl;

/// A track whose audio has been downloaded to on-device storage.
class LocalTrackEntry {
  final String trackId;
  final String normKey;
  final String title;
  final String artist;

  /// File name inside the store's directory (persisted in the index).
  final String fileName;

  /// Absolute `file://` URI, resolved by the store when the entry is read.
  final Uri fileUri;
  final int bytes;
  final String format;
  final Duration duration;
  final String sourceVideoId;
  final DateTime downloadedAt;

  const LocalTrackEntry({
    required this.trackId,
    required this.normKey,
    required this.title,
    required this.artist,
    required this.fileName,
    required this.fileUri,
    required this.bytes,
    required this.format,
    required this.duration,
    required this.sourceVideoId,
    required this.downloadedAt,
  });

  /// Keys that `OfflineState.isTrackDownloaded` matches against.
  Set<String> get matchKeys => {
        trackId,
        LocalTrackStore.cleanIdFor(trackId),
        normKey,
      };

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'normKey': normKey,
        'title': title,
        'artist': artist,
        'fileName': fileName,
        'bytes': bytes,
        'format': format,
        'durationMs': duration.inMilliseconds,
        'sourceVideoId': sourceVideoId,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  /// [fileUri] isn't persisted (app container paths can move); the store
  /// supplies it from its current directory.
  factory LocalTrackEntry.fromJson(Map<String, dynamic> json, {required Uri fileUri}) {
    return LocalTrackEntry(
      trackId: json['trackId'] as String,
      normKey: json['normKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      fileName: json['fileName'] as String,
      fileUri: fileUri,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      format: json['format'] as String? ?? 'm4a',
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
      sourceVideoId: json['sourceVideoId'] as String? ?? '',
      downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// On-device store of downloaded audio plus its index.
///
/// Use [LocalTrackStore.platform] for the process-wide instance: file-backed
/// on native platforms, an always-empty [UnsupportedLocalTrackStore] on web.
abstract interface class LocalTrackStore {
  /// Shared instance for this platform (same object on every call so the
  /// resolver and the download service see one index).
  static LocalTrackStore platform() => _platform ??= impl.createPlatformLocalTrackStore();
  static LocalTrackStore? _platform;

  /// Whether this platform can store files (false on web).
  bool get isSupported;

  /// The downloaded entry for [track] (by id, Spotify-clean id, or
  /// normalized "artist - title"), or null. Entries whose file has gone
  /// missing are dropped and reported as null.
  Future<LocalTrackEntry?> lookup(Track track);

  /// Writes [bytes] for [track] atomically and records it in the index,
  /// replacing any previous download. If [expectedBytes] is given and the
  /// received length differs, nothing is kept and a [LocalTrackStoreException]
  /// is thrown.
  Future<LocalTrackEntry> save(
    Track track,
    Stream<List<int>> bytes, {
    required String format,
    required Duration duration,
    required String sourceVideoId,
    int? expectedBytes,
  });

  /// Deletes [track]'s file and index entry. Returns the bytes freed (0 if
  /// it wasn't downloaded).
  Future<int> remove(Track track);

  /// All downloaded entries, newest first.
  Future<List<LocalTrackEntry>> entries();

  /// Total bytes used by downloaded audio.
  Future<int> totalBytes();

  static String cleanIdFor(String trackId) => trackId.replaceAll('spotify:track:', '').trim();

  /// Same normalization `OfflineState.isTrackDownloaded` uses.
  static String normKeyFor(Track track) =>
      '${track.artist.toLowerCase()} - ${track.title.toLowerCase()}'.trim();
}

class LocalTrackStoreException implements Exception {
  final String message;
  const LocalTrackStoreException(this.message);

  @override
  String toString() => 'LocalTrackStoreException: $message';
}

/// Web (and any platform without a filesystem): nothing is ever local.
class UnsupportedLocalTrackStore implements LocalTrackStore {
  const UnsupportedLocalTrackStore();

  @override
  bool get isSupported => false;

  @override
  Future<LocalTrackEntry?> lookup(Track track) async => null;

  @override
  Future<LocalTrackEntry> save(
    Track track,
    Stream<List<int>> bytes, {
    required String format,
    required Duration duration,
    required String sourceVideoId,
    int? expectedBytes,
  }) {
    throw UnsupportedError('On-device downloads are not available on this platform');
  }

  @override
  Future<int> remove(Track track) async => 0;

  @override
  Future<List<LocalTrackEntry>> entries() async => const [];

  @override
  Future<int> totalBytes() async => 0;
}
