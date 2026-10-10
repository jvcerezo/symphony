import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../domain/entities/track.dart';
import 'local_track_store.dart';

LocalTrackStore createPlatformLocalTrackStore() => IoLocalTrackStore();

/// File-backed [LocalTrackStore]: audio files plus `index.json` in
/// `<application support>/offline_tracks/` (private app storage, not purged
/// like the cache dir).
class IoLocalTrackStore implements LocalTrackStore {
  IoLocalTrackStore({Future<Directory> Function()? baseDirectory})
      : _baseDirectory = baseDirectory ?? _defaultBaseDirectory;

  static const String _indexFileName = 'index.json';

  final Future<Directory> Function() _baseDirectory;
  Future<Directory>? _dir;
  Map<String, Map<String, dynamic>>? _index; // trackId -> entry json
  Future<void> _lock = Future.value();

  static Future<Directory> _defaultBaseDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}offline_tracks');
  }

  @override
  bool get isSupported => true;

  /// Serializes index mutations so concurrent downloads don't clobber it.
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Directory> _directory() {
    return _dir ??= () async {
      final dir = await _baseDirectory();
      await dir.create(recursive: true);
      return dir;
    }()
      ..catchError((Object _) {
        _dir = null; // retry on the next call (e.g. plugin not ready yet)
        return Directory('');
      });
  }

  File _file(Directory dir, String name) => File('${dir.path}${Platform.pathSeparator}$name');

  Future<Map<String, Map<String, dynamic>>> _loadIndex(Directory dir) async {
    if (_index != null) return _index!;
    final file = _file(dir, _indexFileName);
    final index = <String, Map<String, dynamic>>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final raw in (decoded['tracks'] as List<dynamic>? ?? const [])) {
          final json = Map<String, dynamic>.from(raw as Map);
          if (json['trackId'] is String && json['fileName'] is String) {
            index[json['trackId'] as String] = json;
          }
        }
      } catch (e) {
        developer.log('Offline index unreadable, starting empty: $e', name: 'LocalTrackStore');
      }
    }
    return _index = index;
  }

  Future<void> _persistIndex(Directory dir) async {
    final tmp = _file(dir, '$_indexFileName.tmp');
    await tmp.writeAsString(jsonEncode({'version': 1, 'tracks': _index!.values.toList()}), flush: true);
    await tmp.rename(_file(dir, _indexFileName).path);
  }

  LocalTrackEntry _toEntry(Directory dir, Map<String, dynamic> json) =>
      LocalTrackEntry.fromJson(json, fileUri: _file(dir, json['fileName'] as String).uri);

  String? _findKey(Map<String, Map<String, dynamic>> index, Track track) {
    if (index.containsKey(track.id)) return track.id;
    final cleanId = LocalTrackStore.cleanIdFor(track.id);
    final norm = LocalTrackStore.normKeyFor(track);
    for (final e in index.entries) {
      if (LocalTrackStore.cleanIdFor(e.key) == cleanId || e.value['normKey'] == norm) return e.key;
    }
    return null;
  }

  @override
  Future<LocalTrackEntry?> lookup(Track track) => _synchronized(() async {
        final dir = await _directory();
        final index = await _loadIndex(dir);
        final key = _findKey(index, track);
        if (key == null) return null;
        final json = index[key]!;
        if (!await _file(dir, json['fileName'] as String).exists()) {
          index.remove(key);
          await _persistIndex(dir);
          return null;
        }
        return _toEntry(dir, json);
      });

  @override
  Future<LocalTrackEntry> save(
    Track track,
    Stream<List<int>> bytes, {
    required String format,
    required Duration duration,
    required String sourceVideoId,
    int? expectedBytes,
  }) async {
    final dir = await _directory();
    final fileName = '${_safeName(track.id)}.${_extensionFor(format)}';
    // Unique part file so two downloads of the same track can't interleave.
    final part = _file(dir, '$fileName.${DateTime.now().microsecondsSinceEpoch}.part');

    var written = 0;
    final sink = part.openWrite();
    try {
      await for (final chunk in bytes) {
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (written == 0 || (expectedBytes != null && expectedBytes > 0 && written != expectedBytes)) {
      await _deleteQuietly(part);
      throw LocalTrackStoreException(
        'Incomplete download for "${track.title}": $written of ${expectedBytes ?? '?'} bytes',
      );
    }

    return _synchronized(() async {
      final index = await _loadIndex(dir);
      final previousKey = _findKey(index, track);
      if (previousKey != null) {
        final previousName = index.remove(previousKey)!['fileName'] as String;
        if (previousName != fileName) await _deleteQuietly(_file(dir, previousName));
      }
      await part.rename(_file(dir, fileName).path);

      final json = LocalTrackEntry(
        trackId: track.id,
        normKey: LocalTrackStore.normKeyFor(track),
        title: track.title,
        artist: track.artist,
        fileName: fileName,
        fileUri: _file(dir, fileName).uri,
        bytes: written,
        format: format,
        duration: duration,
        sourceVideoId: sourceVideoId,
        downloadedAt: DateTime.now(),
      ).toJson();
      index[track.id] = json;
      await _persistIndex(dir);
      return _toEntry(dir, json);
    });
  }

  @override
  Future<int> remove(Track track) => _synchronized(() async {
        final dir = await _directory();
        final index = await _loadIndex(dir);
        final key = _findKey(index, track);
        if (key == null) return 0;
        final json = index.remove(key)!;
        await _deleteQuietly(_file(dir, json['fileName'] as String));
        await _persistIndex(dir);
        return (json['bytes'] as num?)?.toInt() ?? 0;
      });

  @override
  Future<List<LocalTrackEntry>> entries() => _synchronized(() async {
        final dir = await _directory();
        final index = await _loadIndex(dir);
        final list = index.values.map((j) => _toEntry(dir, j)).toList()
          ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
        return list;
      });

  @override
  Future<int> totalBytes() async {
    final all = await entries();
    return all.fold<int>(0, (sum, e) => sum + e.bytes);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _safeName(String trackId) {
    final cleaned = trackId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final short = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
    // Hash suffix keeps ids that only differ in stripped characters distinct.
    return '${short}_${_fnv1a(trackId).toRadixString(16)}';
  }

  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(s)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _extensionFor(String format) {
    final f = format.toLowerCase();
    if (f.contains('webm') || f.contains('opus')) return 'webm';
    if (f.contains('mp3') || f.contains('mpeg')) return 'mp3';
    return 'm4a';
  }
}
