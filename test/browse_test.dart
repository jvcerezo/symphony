import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/browse/data/genre_catalog.dart';
import 'package:symphony/features/browse/data/genre_playlist_service.dart';
import 'package:symphony/features/browse/presentation/genre_providers.dart';
import 'package:symphony/features/browse/presentation/genre_section.dart';
import 'package:symphony/features/playlist_import/data/services/apple_music_web_service.dart';
import 'package:symphony/features/playlist_import/data/services/spotify_embed_scraper_service.dart';
import 'package:symphony/features/playlist_import/data/services/universal_playlist_importer_service.dart';
import 'package:symphony/features/playlist_import/data/services/youtube_playlist_page.dart';
import 'package:symphony/features/playlist_import/domain/entities/playlist_summary.dart';

String _appleHtml(Object data) =>
    '<html><script type="application/json" id="serialized-server-data">${jsonEncode(data)}</script></html>';

Map _appleItem(String kind, String id, String title, {String? subtitle, Map? extra}) => {
      'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      'artwork': {
        'dictionary': {'url': 'https://img/$id/{w}x{h}bb.{f}'}
      },
      'contentDescriptor': {
        'kind': kind,
        'identifiers': {'storeAdamID': id},
        'url': 'https://music.apple.com/us/$kind/x/$id',
      },
      ...?extra,
    };

Map _lockup(String videoId, String title, String channel, String length) => {
      'lockupViewModel': {
        'contentId': videoId,
        'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
        'contentImage': {
          'thumbnailViewModel': {
            'overlays': [
              {
                'thumbnailBottomOverlayViewModel': {
                  'badges': [
                    {
                      'thumbnailBadgeViewModel': {'text': length}
                    }
                  ]
                }
              }
            ]
          }
        },
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {'content': title},
            'metadata': {
              'contentMetadataViewModel': {
                'metadataRows': [
                  {
                    'metadataParts': [
                      {
                        'text': {'content': channel}
                      }
                    ]
                  }
                ]
              }
            },
          }
        },
      }
    };

void main() {
  group('Apple Music web pages', () {
    test('search lists playlists once each, Apple editorial first', () {
      final html = _appleHtml({
        'data': [
          _appleItem('song', '1', 'A Song'),
          _appleItem('playlist', 'pl.user', 'Someone Lofi', subtitle: 'Playlist · DJ Someone'),
          _appleItem('playlist', 'pl.apple', 'Lo-Fi Chill', subtitle: 'Playlist · Apple Music Chill'),
          _appleItem('playlist', 'pl.apple', 'Lo-Fi Chill', subtitle: 'Playlist · Apple Music Chill'),
        ]
      });
      final found = AppleMusicWebService.parseSearchPlaylists(html);
      expect(found.map((p) => p.id), ['pl.apple', 'pl.user']);
      expect(found.first.subtitle, 'Apple Music Chill');
      expect(found.first.coverUrl, 'https://img/pl.apple/600x600bb.jpg');
    });

    test('reads a playlist page into songs', () {
      final html = _appleHtml({
        'data': {
          'sections': [
            {
              'id': 'playlist-detail-header-section - pl.abc',
              'items': [
                _appleItem('playlist', 'pl.abc', 'Lo-Fi Chill', extra: {
                  'subtitleLinks': [
                    {'title': 'Apple Music Chill'}
                  ]
                })
              ],
            },
            {
              'id': 'track-list - pl.abc',
              'items': [
                _appleItem('song', '111', 'KANNON', extra: {
                  'artistName': 'YIIN',
                  'duration': 109853,
                  'tertiaryLinks': [
                    {'title': 'METTA - EP'}
                  ],
                }),
              ],
            },
          ]
        }
      });
      final pl = AppleMusicWebService.parsePlaylist(html, url: 'https://music.apple.com/us/playlist/lo-fi-chill/pl.abc')!;
      expect(pl.title, 'Lo-Fi Chill');
      expect(pl.ownerName, 'Apple Music Chill');
      final t = pl.tracks.single;
      expect([t.id, t.title, t.artist, t.album], ['am_111', 'KANNON', 'YIIN', 'METTA - EP']);
      expect(t.expectedDuration, const Duration(milliseconds: 109853));
    });

    test('non-playlist Apple links are refused, not swapped for a chart', () async {
      final importer = UniversalPlaylistImporterService(httpClient: MockClient((_) async => http.Response('', 500)));
      expect(
        importer.importPlaylist('https://music.apple.com/us/album/after-hours/1499378108'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('YouTube playlist page', () {
    test('reads videos, channel and length from the current layout', () {
      final data = {
        'metadata': {
          'playlistMetadataRenderer': {'title': 'Old School RnB', 'description': ''}
        },
        'contents': [
          _lockup('abc', 'Foolish', 'Ashanti - Topic', '3:48'),
          _lockup('abc', 'Foolish', 'Ashanti - Topic', '3:48'),
          _lockup('def', 'No Scrubs', 'TLCVEVO', '1:02:03'),
        ],
      };
      final html = '<script>var ytInitialData = ${jsonEncode(data)};</script>';
      final pl = YouTubePlaylistPage.parse(html, playlistId: 'PL1')!;
      expect(pl.title, 'Old School RnB');
      expect(pl.tracks.map((t) => t.id), ['yt_abc', 'yt_def']);
      expect(pl.tracks.map((t) => t.artist), ['Ashanti', 'TLC']);
      expect(pl.tracks.first.expectedDuration, const Duration(minutes: 3, seconds: 48));
      expect(pl.tracks.last.expectedDuration, const Duration(hours: 1, minutes: 2, seconds: 3));
    });

    test('a page without videos gives nothing', () {
      expect(YouTubePlaylistPage.parse('<html></html>', playlistId: 'x'), isNull);
    });
  });

  group('GenrePlaylistService', () {
    final genre = GenreCatalog.all.first;

    test('Spotify reads each editorial playlist by id', () async {
      final requested = <String>[];
      final spotify = SpotifyEmbedScraperService(
        httpClient: MockClient((req) async {
          requested.add(req.url.path);
          final id = req.url.pathSegments.last;
          final next = {
            'props': {
              'pageProps': {
                'state': {
                  'data': {
                    'entity': {
                      'name': 'List $id',
                      'subtitle': 'Spotify',
                      'coverArt': {
                        'sources': [
                          {'url': 'https://i.scdn.co/image/ab67706f00000002cover'}
                        ]
                      },
                      'trackList': [{}, {}],
                    }
                  }
                }
              }
            }
          };
          return http.Response('<script id="__NEXT_DATA__" type="application/json">${jsonEncode(next)}</script>', 200);
        }),
      );
      final service = GenrePlaylistService(spotify: spotify, appleSearch: (_, __) async => [], youtubeSearch: (_, __) async => []);
      final found = await service.playlistsFor(genre, PlaylistSource.spotify);
      expect(found.map((p) => p.id), genre.spotifyPlaylistIds);
      expect(found.first.trackCount, 2);
      expect(found.first.coverUrl, 'https://i.scdn.co/image/ab67706f00000003cover');
      expect(requested.every((p) => p.startsWith('/embed/playlist/')), isTrue);
    });

    test('Apple Music and YouTube search with the genre terms', () async {
      final queries = <String>[];
      PlaylistSearch record(PlaylistSource source) => (q, limit) async {
            queries.add(q);
            return [PlaylistSummary(source: source, id: q, title: q, link: q)];
          };
      final service = GenrePlaylistService(
        spotify: SpotifyEmbedScraperService(httpClient: MockClient((_) async => http.Response('', 404))),
        appleSearch: record(PlaylistSource.appleMusic),
        youtubeSearch: record(PlaylistSource.youtube),
      );
      await service.playlistsFor(genre, PlaylistSource.appleMusic);
      await service.playlistsFor(genre, PlaylistSource.youtube);
      expect(queries, [genre.query, '${genre.query} playlist']);
    });
  });

  testWidgets('genre page shows each source, with errors kept to that source', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final genre = GenreCatalog.all.first;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        genrePlaylistsProvider((genre, PlaylistSource.spotify)).overrideWith((ref) async => [
              const PlaylistSummary(source: PlaylistSource.spotify, id: 's1', title: "Today's Top Hits", link: 'x'),
            ]),
        genrePlaylistsProvider((genre, PlaylistSource.appleMusic))
            .overrideWith((ref) async => throw Exception('offline')),
        genrePlaylistsProvider((genre, PlaylistSource.youtube)).overrideWith((ref) async => []),
      ],
      child: MaterialApp(home: Scaffold(body: GenreSection(genre: genre, isDesktop: true))),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text(genre.title), findsOneWidget);
    expect(find.text("Today's Top Hits"), findsOneWidget);
    expect(find.text("Couldn't load playlists from Apple Music."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No ${genre.title} playlists found on YouTube.'), findsOneWidget);
  });
}
