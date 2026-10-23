import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../playlist_import/domain/entities/spotify_playlist.dart';
import '../data/deezer_catalog.dart';
import '../data/listening_history.dart';
import '../data/mix_builder.dart';
import '../data/play_recorder.dart';
import '../domain/listening_log.dart';
import '../domain/taste_profile.dart';

final listeningLogStoreProvider = Provider<ListeningLogStore>((ref) => PrefsListeningLogStore());

/// What was listened to on this device.
final listeningHistoryProvider = StateNotifierProvider<ListeningHistory, ListeningLog>((ref) {
  return ListeningHistory(store: ref.watch(listeningLogStoreProvider));
});

final deezerCatalogProvider = Provider<DeezerCatalog>((ref) {
  final catalog = DeezerCatalog();
  ref.onDispose(catalog.dispose);
  return catalog;
});

final mixBuilderProvider = Provider<MixBuilder>((ref) => MixBuilder(catalog: ref.watch(deezerCatalogProvider)));

/// Keep playing similar songs when the queue runs out.
final autoplayProvider = StateProvider<bool>((ref) => true);

/// The user's taste, from their plays and, before there are many, the
/// playlists they imported.
final tasteProfileProvider = Provider<TasteProfile>((ref) {
  final log = ref.watch(listeningHistoryProvider);
  final imported = ref.watch(importedPlaylistsProvider).where((p) => !MixBuilder.isMix(p));
  return TasteProfile.from(log, now: DateTime.now(), seedTracks: imported.expand((p) => p.tracks));
});

/// Mixes from the user's own plays (On Repeat, Recently Played). No network.
final localMixesProvider = Provider<List<SpotifyPlaylist>>((ref) {
  final log = ref.watch(listeningHistoryProvider);
  final builder = ref.watch(mixBuilderProvider);
  return [
    builder.onRepeat(log, now: DateTime.now()),
    builder.recentlyPlayed(log),
  ].whereType<SpotifyPlaylist>().toList();
});

/// Daily Mixes, Discover Weekly and Top Hits: built with Deezer once a day
/// (Discover Weekly once a week) and kept, so Home opens with them at once.
final madeForYouProvider = StateNotifierProvider<MadeForYouNotifier, AsyncValue<List<SpotifyPlaylist>>>((ref) {
  return MadeForYouNotifier(
    builder: ref.watch(mixBuilderProvider),
    store: ref.watch(listeningLogStoreProvider),
    taste: () => ref.read(tasteProfileProvider),
    whenHistoryLoaded: () => ref.read(listeningHistoryProvider.notifier).loaded,
  );
});

class MadeForYouNotifier extends StateNotifier<AsyncValue<List<SpotifyPlaylist>>> {
  MadeForYouNotifier({
    required MixBuilder builder,
    required ListeningLogStore store,
    required TasteProfile Function() taste,
    Future<void> Function()? whenHistoryLoaded,
    DateTime Function()? clock,
    bool? online,
  })  : _builder = builder,
        _store = store,
        _taste = taste,
        _whenHistoryLoaded = whenHistoryLoaded,
        _clock = clock ?? DateTime.now,
        // The browser can't reach Deezer (no CORS).
        _online = online ?? !kIsWeb,
        super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  static const cacheKey = 'symphony_made_for_you';

  final MixBuilder _builder;
  final ListeningLogStore _store;
  final TasteProfile Function() _taste;
  final Future<void> Function()? _whenHistoryLoaded;
  final DateTime Function() _clock;
  final bool _online;
  Future<void>? _running;

  /// Rebuilds what is out of date; with [force], everything.
  Future<void> refresh({bool force = false}) => _running ??= _refresh(force).whenComplete(() => _running = null);

  Future<void> _refresh(bool force) async {
    final cache = await _readCache();
    if (state is AsyncLoading && cache.all.isNotEmpty) state = AsyncValue.data(cache.all);
    if (!_online) {
      state = AsyncValue.data(cache.all);
      return;
    }
    await _whenHistoryLoaded?.call();

    final now = _clock();
    final day = _dayKey(now);
    final week = _dayKey(MixBuilder.weekStart(now));
    final taste = _taste();

    try {
      var next = cache;
      if (force ||
          cache.day != day ||
          (cache.daily.isEmpty && !taste.isEmpty) ||
          (taste.isEmpty && !cache.hasStarter)) {
        final daily = await _builder.dailyMixes(taste, now: now);
        final top = await _builder.topHits();
        // Nothing played yet: genre charts until there are mixes of their own.
        final starter = taste.isEmpty ? await _builder.starterMixes() : const <SpotifyPlaylist>[];
        // A build that failed (offline) keeps the last mixes and is tried
        // again next time instead of waiting for tomorrow.
        final built = (daily.isNotEmpty || taste.isEmpty) && top != null;
        next = next.copyWith(
          daily: taste.isEmpty ? const [] : (daily.isEmpty ? next.daily : daily),
          top: top ?? next.top,
          starter: taste.isEmpty ? (starter.isEmpty ? next.starter : starter) : const [],
          day: built ? day : next.day,
        );
      }
      if (force || cache.week != week || (cache.discover == null && !taste.isEmpty)) {
        final discover = await _builder.discoverWeekly(taste, now: now);
        next = next.copyWith(discover: discover ?? next.discover, week: discover != null ? week : next.week);
      }
      state = AsyncValue.data(next.all);
      await _store.write(cacheKey, jsonEncode(next.toJson()));
    } catch (e, st) {
      developer.log('Building mixes failed: $e', name: 'ForYou');
      state = cache.all.isEmpty ? AsyncValue.error(e, st) : AsyncValue.data(cache.all);
    }
  }

  Future<_MixCache> _readCache() async {
    try {
      final raw = await _store.read(cacheKey);
      if (raw != null) return _MixCache.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return const _MixCache();
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

class _MixCache {
  final String? day;
  final String? week;
  final List<SpotifyPlaylist> daily;
  final SpotifyPlaylist? discover;
  final SpotifyPlaylist? top;

  /// Genre charts for someone with no plays yet ([MixBuilder.starterMixes]).
  final List<SpotifyPlaylist> starter;

  /// False for a cache kept before there were starter mixes: build them now
  /// rather than tomorrow.
  final bool hasStarter;

  const _MixCache(
      {this.day,
      this.week,
      this.daily = const [],
      this.discover,
      this.top,
      this.starter = const [],
      this.hasStarter = false});

  List<SpotifyPlaylist> get all =>
      [...daily, if (discover != null) discover!, if (top != null) top!, ...starter];

  _MixCache copyWith(
          {String? day,
          String? week,
          List<SpotifyPlaylist>? daily,
          SpotifyPlaylist? discover,
          SpotifyPlaylist? top,
          List<SpotifyPlaylist>? starter}) =>
      _MixCache(
        day: day ?? this.day,
        week: week ?? this.week,
        daily: daily ?? this.daily,
        discover: discover ?? this.discover,
        top: top ?? this.top,
        starter: starter ?? this.starter,
        hasStarter: hasStarter || starter != null,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'week': week,
        'daily': daily.map((p) => p.toJson()).toList(),
        'discover': discover?.toJson(),
        'top': top?.toJson(),
        'starter': starter.map((p) => p.toJson()).toList(),
      };

  static _MixCache fromJson(Map<String, dynamic> json) {
    SpotifyPlaylist? one(Object? raw) => raw is Map ? SpotifyPlaylist.fromJson(Map<String, dynamic>.from(raw)) : null;
    List<SpotifyPlaylist> many(Object? raw) =>
        raw is List ? raw.map(one).whereType<SpotifyPlaylist>().toList() : const [];
    return _MixCache(
      day: json['day'] as String?,
      week: json['week'] as String?,
      daily: many(json['daily']),
      discover: one(json['discover']),
      top: one(json['top']),
      starter: many(json['starter']),
      hasStarter: json.containsKey('starter'),
    );
  }
}

/// Records what is played into [listeningHistoryProvider].
final playRecorderProvider = Provider<PlayRecorder>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final history = ref.read(listeningHistoryProvider.notifier);
  final recorder = PlayRecorder(
    mediaItems: handler.mediaItem,
    states: handler.playbackState,
    currentTrack: () => handler.currentTrack,
    onPlay: history.record,
    onProgress: (e) => unawaited(history.setInProgress(e)),
  );
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// App start (from `main.dart`): records what is played and, on native,
/// hands the player songs to continue with when a queue runs out.
void startForYou(ProviderContainer container) {
  container.read(playRecorderProvider);
  if (kIsWeb) return;
  container.read(audioHandlerProvider).autoplay = (last, queue) async {
    if (!container.read(autoplayProvider)) return const [];
    return container.read(mixBuilderProvider).radioAfterQueue(queue, taste: container.read(tasteProfileProvider));
  };
}
